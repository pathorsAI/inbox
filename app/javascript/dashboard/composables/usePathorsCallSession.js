import { readonly, ref } from 'vue';
import PathorsCallsAPI from 'dashboard/api/pathorsCalls';

/**
 * Human takeover of a Pathors voice call.
 *
 * The Pathors backend owns the LiveKit room the AI agent is already speaking
 * in; POST .../pathors/calls/:id/join asks it to yield and hands back a
 * participant token. Everything below is just: redeem the token, publish the
 * mic, play whatever comes back.
 *
 * Getting out comes in two flavours: `leave` only drops this browser out of the
 * room (the AI picks the caller back up), while `hangup` asks the backend to
 * end the call for everyone.
 *
 * State is module-level on purpose. Every voice_call bubble in the thread
 * instantiates this composable, and a browser can only be in one call at a
 * time — a per-instance ref would let two bubbles (or two threads) join in
 * parallel and fight over the same microphone.
 */

export const PATHORS_JOIN_ERROR = {
  ALREADY_CLAIMED: 'already_claimed',
  CALL_ENDED: 'call_ended',
  MEDIA_DENIED: 'media_denied',
  UNAVAILABLE: 'unavailable',
  // Ending the call failed for a reason other than "it is already over"; the
  // agent is still in the room and can keep talking or leave instead.
  HANGUP_FAILED: 'hangup_failed',
};

// The relay's answers for a call that no longer exists (backend 404, or our own
// 410 for a call already terminal) — the goal of hanging up is met either way.
const CALL_OVER_STATUSES = new Set([404, 410]);

const AUDIO_ELEMENT_CLASS = 'pathors-call-audio';
const DURATION_TICK_MS = 1000;

const isJoining = ref(false);
const isJoined = ref(false);
const isHangingUp = ref(false);
const error = ref(null);
const durationSeconds = ref(0);
// Which call this tab is in, so a second bubble can tell "someone else's call
// is live" from "my call is live".
const activeCallId = ref(null);
// The browser's autoplay policy refused to play the room's audio. By the time
// remote tracks arrive the "join" click's user gesture has long expired (HTTP
// round-trip + dynamic import + connect + mic prompt), so Safari — and Chrome
// often enough — silently mutes the caller. The bubble shows an "enable audio"
// button while this is true; that click is a fresh gesture.
const isAudioBlocked = ref(false);

let room = null;
let durationTimer = null;
let attachedElements = [];

const stopDurationTimer = () => {
  if (!durationTimer) return;
  clearInterval(durationTimer);
  durationTimer = null;
};

const startDurationTimer = () => {
  stopDurationTimer();
  durationSeconds.value = 0;
  const startedAt = Date.now();
  durationTimer = setInterval(() => {
    durationSeconds.value = Math.floor((Date.now() - startedAt) / 1000);
  }, DURATION_TICK_MS);
};

const detachAllAudio = () => {
  attachedElements.forEach(el => {
    el.srcObject = null;
    el.remove();
  });
  attachedElements = [];
};

const attachAudioTrack = track => {
  if (track?.kind !== 'audio') return;
  const el = track.attach();
  el.autoplay = true;
  el.classList.add(AUDIO_ELEMENT_CLASS);
  el.style.display = 'none';
  document.body.appendChild(el);
  attachedElements.push(el);
  // Autoplay policies can refuse here: the "join" gesture is gone by the time
  // tracks arrive. Surface it so the agent gets a button to unlock playback
  // instead of sitting in a call they cannot hear.
  const played = el.play?.();
  if (played?.catch) {
    played.catch(err => {
      // eslint-disable-next-line no-console
      console.warn('[pathors-call] audio playback blocked', err);
      isAudioBlocked.value = true;
    });
  }
};

const detachAudioTrack = track => {
  if (track?.kind !== 'audio') return;
  const elements = track.detach();
  elements.forEach(el => {
    attachedElements = attachedElements.filter(item => item !== el);
    el.remove();
  });
};

const resetSession = () => {
  stopDurationTimer();
  detachAllAudio();
  room = null;
  isJoined.value = false;
  isJoining.value = false;
  isHangingUp.value = false;
  activeCallId.value = null;
  durationSeconds.value = 0;
  isAudioBlocked.value = false;
};

// Maps the relay's HTTP answer onto a code the bubble can phrase. 409 is the
// race we expect most often (another dashboard answered first); 404/410 mean
// the call is already over.
const errorCodeFor = requestError => {
  const status = requestError?.response?.status;
  if (status === 409) return PATHORS_JOIN_ERROR.ALREADY_CLAIMED;
  if (status === 404 || status === 410) return PATHORS_JOIN_ERROR.CALL_ENDED;
  return PATHORS_JOIN_ERROR.UNAVAILABLE;
};

// Local teardown shared by leave and hangup. Resets first so the UI flips back
// immediately even if disconnect() hangs; the Disconnected handler is a no-op
// once state is already clear.
const teardown = async () => {
  const activeRoom = room;
  resetSession();
  if (!activeRoom) return;
  try {
    await activeRoom.disconnect();
  } catch (err) {
    // The room is gone either way (the backend may already have deleted it);
    // nothing to retry, but leave a trace for debugging.
    // eslint-disable-next-line no-console
    console.debug('[pathors-call] disconnect after teardown failed', err);
  }
};

const connectToRoom = async credentials => {
  const { Room, RoomEvent } = await import('livekit-client');

  // Kept as a local so the listeners below never read the module-level `room`
  // after a reset has nulled it.
  const lkRoom = new Room();
  room = lkRoom;
  room.on(RoomEvent.TrackSubscribed, track => attachAudioTrack(track));
  room.on(RoomEvent.TrackUnsubscribed, track => detachAudioTrack(track));
  // LiveKit tracks whether the browser will let it play audio; mirror that so
  // the bubble can offer an unlock button (and drop it once playback starts).
  room.on(RoomEvent.AudioPlaybackStatusChanged, () => {
    if (room !== lkRoom) return;
    isAudioBlocked.value = !lkRoom.canPlaybackAudio;
  });
  // A remote disconnect (call ended, token expired, agent kicked) has to land
  // back on the same teardown as an explicit leave, or the bubble stays stuck
  // showing "leave".
  room.on(RoomEvent.Disconnected, () => resetSession());

  await room.connect(credentials.serverUrl, credentials.token);
  await room.localParticipant.setMicrophoneEnabled(true);

  // Try to unlock playback now; without a live user gesture this may reject,
  // in which case canPlaybackAudio stays false and the bubble asks for a tap.
  try {
    await lkRoom.startAudio();
  } catch (_) {
    /* noop — reflected through canPlaybackAudio below */
  }
  // The room may have dropped while startAudio() was pending; don't resurrect
  // the flag on a session that has already been torn down.
  if (room === lkRoom) isAudioBlocked.value = !lkRoom.canPlaybackAudio;
};

export function usePathorsCallSession() {
  /**
   * @param {{ accountId?: number|string, callId: number|string }} params
   * @returns {Promise<boolean>} true when the agent is in the room
   */
  const join = async ({ accountId, callId } = {}) => {
    if (!callId) return false;
    // Guard both directions: a second click on this bubble, and a click on a
    // different bubble while a call is already live.
    if (isJoining.value || isJoined.value) return false;

    isJoining.value = true;
    error.value = null;

    let credentials = null;
    try {
      credentials = await PathorsCallsAPI.join(callId, accountId);
    } catch (requestError) {
      error.value = errorCodeFor(requestError);
      isJoining.value = false;
      return false;
    }

    if (!credentials?.token || !credentials?.serverUrl) {
      error.value = PATHORS_JOIN_ERROR.UNAVAILABLE;
      isJoining.value = false;
      return false;
    }

    try {
      await connectToRoom(credentials);
    } catch (connectError) {
      // getUserMedia rejections are the one failure the agent can fix
      // themselves (grant the mic), so they get their own message.
      const isMediaError = /NotAllowed|Permission|NotFound/i.test(
        connectError?.name || connectError?.message || ''
      );
      try {
        await room?.disconnect();
      } catch (_) {
        /* noop — nothing to tear down */
      }
      resetSession();
      error.value = isMediaError
        ? PATHORS_JOIN_ERROR.MEDIA_DENIED
        : PATHORS_JOIN_ERROR.UNAVAILABLE;
      return false;
    }

    isJoining.value = false;
    isJoined.value = true;
    activeCallId.value = callId;
    startDurationTimer();
    return true;
  };

  const leave = () => teardown();

  /**
   * Ends the live call for everyone. On success the backend has the voice
   * agent delete the room, so we tear down locally right away instead of
   * waiting for the Disconnected event. Any failure other than "the call is
   * already over" keeps the agent in the room: dropping them on, say, a 502
   * would leave the caller with the AI while the agent believes it hung up.
   * @param {{ accountId?: number|string }} params
   * @returns {Promise<boolean>} true when this browser is out of the call
   */
  const hangup = async ({ accountId } = {}) => {
    const callId = activeCallId.value;
    if (!isJoined.value || !callId || isHangingUp.value) return false;

    const sessionRoom = room;
    isHangingUp.value = true;
    error.value = null;

    let callOver = true;
    try {
      await PathorsCallsAPI.hangup(callId, accountId);
    } catch (requestError) {
      callOver = CALL_OVER_STATUSES.has(requestError?.response?.status);
    }

    // The room can drop while the request is in flight (the backend's teardown
    // racing its own response, or the agent pressing leave); that session is
    // already reset, and a newer one must not be touched.
    if (room !== sessionRoom) return true;

    if (callOver) {
      await teardown();
      return true;
    }

    isHangingUp.value = false;
    error.value = PATHORS_JOIN_ERROR.HANGUP_FAILED;
    return false;
  };

  /**
   * Unlocks room audio after the browser's autoplay policy blocked it. Must be
   * called from a user gesture (the bubble's "enable audio" click).
   * @returns {Promise<void>}
   */
  const enableAudio = async () => {
    const activeRoom = room;
    if (!activeRoom) return;
    try {
      await activeRoom.startAudio();
      await Promise.all(
        attachedElements.map(el =>
          Promise.resolve(el.play?.()).catch(() => {
            /* noop — one stubborn element shouldn't block the rest */
          })
        )
      );
      isAudioBlocked.value = !activeRoom.canPlaybackAudio;
    } catch (err) {
      // eslint-disable-next-line no-console
      console.warn('[pathors-call] could not enable audio', err);
      isAudioBlocked.value = true;
    }
  };

  const isActiveCall = callId =>
    activeCallId.value != null && String(activeCallId.value) === String(callId);

  return {
    join,
    // Alias kept for call sites that read better as a verb+noun.
    joinCall: join,
    leave,
    hangup,
    enableAudio,
    isAudioBlocked: readonly(isAudioBlocked),
    isJoining: readonly(isJoining),
    isJoined: readonly(isJoined),
    isHangingUp: readonly(isHangingUp),
    error: readonly(error),
    durationSeconds: readonly(durationSeconds),
    activeCallId: readonly(activeCallId),
    isActiveCall,
  };
}

// Test seam: the module-level singleton would otherwise leak between specs.
export const resetPathorsCallSession = () => {
  room = null;
  resetSession();
  error.value = null;
};
