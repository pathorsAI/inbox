import {
  usePathorsCallSession,
  resetPathorsCallSession,
  PATHORS_JOIN_ERROR,
} from '../usePathorsCallSession';
import PathorsCallsAPI from 'dashboard/api/pathorsCalls';

vi.mock('dashboard/api/pathorsCalls', () => ({
  default: { join: vi.fn(), hangup: vi.fn() },
}));

const ROOM_EVENT = {
  TrackSubscribed: 'trackSubscribed',
  TrackUnsubscribed: 'trackUnsubscribed',
  Disconnected: 'disconnected',
  AudioPlaybackStatusChanged: 'audioPlaybackChanged',
};

// Hoisted so the vi.mock factory below (which runs before the module body) can
// reach the same room registry the tests assert on.
const { FakeRoom, rooms, micState } = vi.hoisted(() => {
  const registry = [];
  // Set by a test to make the next room's microphone request reject.
  const state = { nextError: null, nextAudioBlocked: false };

  class Room {
    constructor() {
      this.handlers = {};
      this.connect = vi.fn().mockResolvedValue(undefined);
      this.disconnect = vi.fn().mockResolvedValue(undefined);
      // Playback allowed by default; tests flip it to simulate autoplay blocks.
      // Set by a test to make the next room behave as if autoplay is refused.
      const audioBlocked = state.nextAudioBlocked;
      state.nextAudioBlocked = false;
      this.canPlaybackAudio = !audioBlocked;
      this.startAudio = audioBlocked
        ? vi.fn().mockRejectedValue(new Error('NotAllowedError'))
        : vi.fn().mockResolvedValue(undefined);
      const micError = state.nextError;
      state.nextError = null;
      this.localParticipant = {
        setMicrophoneEnabled: micError
          ? vi.fn().mockRejectedValue(micError)
          : vi.fn().mockResolvedValue(undefined),
      };
      registry.push(this);
    }

    on(event, handler) {
      this.handlers[event] = handler;
      return this;
    }

    emit(event, ...args) {
      this.handlers[event]?.(...args);
    }
  }

  return { FakeRoom: Room, rooms: registry, micState: state };
});

vi.mock('livekit-client', () => ({
  Room: FakeRoom,
  RoomEvent: {
    TrackSubscribed: 'trackSubscribed',
    TrackUnsubscribed: 'trackUnsubscribed',
    Disconnected: 'disconnected',
    AudioPlaybackStatusChanged: 'audioPlaybackChanged',
  },
}));

const credentials = {
  token: 'lk-token',
  serverUrl: 'wss://livekit.example',
  roomName: 'room-1',
  participantIdentity: 'chatwoot-human-7',
  yieldDelivered: true,
};

const rejectWith = status => {
  const error = new Error(`Request failed with status ${status}`);
  error.response = { status };
  return Promise.reject(error);
};

describe('usePathorsCallSession', () => {
  beforeEach(() => {
    rooms.length = 0;
    micState.nextError = null;
    micState.nextAudioBlocked = false;
    vi.clearAllMocks();
    resetPathorsCallSession();
  });

  afterEach(() => {
    resetPathorsCallSession();
  });

  it('joins the room and publishes the microphone', async () => {
    PathorsCallsAPI.join.mockResolvedValue(credentials);
    const { join, isJoined, isJoining, isActiveCall } = usePathorsCallSession();

    const joined = await join({ accountId: 3, callId: 42 });

    expect(joined).toBe(true);
    expect(PathorsCallsAPI.join).toHaveBeenCalledWith(42, 3);
    expect(rooms[0].connect).toHaveBeenCalledWith(
      'wss://livekit.example',
      'lk-token'
    );
    expect(rooms[0].localParticipant.setMicrophoneEnabled).toHaveBeenCalledWith(
      true
    );
    expect(isJoined.value).toBe(true);
    expect(isJoining.value).toBe(false);
    expect(isActiveCall(42)).toBe(true);
  });

  it('attaches subscribed audio tracks to a hidden autoplay element', async () => {
    PathorsCallsAPI.join.mockResolvedValue(credentials);
    PathorsCallsAPI.hangup.mockResolvedValue({ ok: true });
    const { join, hangup } = usePathorsCallSession();
    await join({ accountId: 3, callId: 42 });

    const element = document.createElement('audio');
    element.play = vi.fn().mockResolvedValue(undefined);
    const track = {
      kind: 'audio',
      attach: () => element,
      detach: () => [element],
    };

    rooms[0].emit(ROOM_EVENT.TrackSubscribed, track);

    expect(element.autoplay).toBe(true);
    expect(element.style.display).toBe('none');
    expect(document.body.contains(element)).toBe(true);

    await hangup({ accountId: 3 });

    expect(document.body.contains(element)).toBe(false);
  });

  it('reports a 409 as already claimed and stays out of the room', async () => {
    PathorsCallsAPI.join.mockImplementation(() => rejectWith(409));
    const { join, error, isJoined } = usePathorsCallSession();

    const joined = await join({ accountId: 3, callId: 42 });

    expect(joined).toBe(false);
    expect(error.value).toBe(PATHORS_JOIN_ERROR.ALREADY_CLAIMED);
    expect(isJoined.value).toBe(false);
    expect(rooms).toHaveLength(0);
  });

  it('reports a 404 and a 410 as an ended call', async () => {
    const { join, error } = usePathorsCallSession();

    PathorsCallsAPI.join.mockImplementation(() => rejectWith(404));
    await join({ accountId: 3, callId: 42 });
    expect(error.value).toBe(PATHORS_JOIN_ERROR.CALL_ENDED);

    resetPathorsCallSession();
    PathorsCallsAPI.join.mockImplementation(() => rejectWith(410));
    await join({ accountId: 3, callId: 42 });
    expect(error.value).toBe(PATHORS_JOIN_ERROR.CALL_ENDED);
  });

  it('refuses a second join while a call is already live', async () => {
    PathorsCallsAPI.join.mockResolvedValue(credentials);
    const { join } = usePathorsCallSession();
    await join({ accountId: 3, callId: 42 });

    // A different bubble, sharing the module-level singleton.
    const second = usePathorsCallSession();
    const joined = await second.join({ accountId: 3, callId: 99 });

    expect(joined).toBe(false);
    expect(PathorsCallsAPI.join).toHaveBeenCalledTimes(1);
    expect(rooms).toHaveLength(1);
  });

  it('clears the session when the room drops the connection', async () => {
    PathorsCallsAPI.join.mockResolvedValue(credentials);
    const { join, isJoined } = usePathorsCallSession();
    await join({ accountId: 3, callId: 42 });

    rooms[0].emit(ROOM_EVENT.Disconnected);

    expect(isJoined.value).toBe(false);
  });

  it('surfaces a missing token as an unavailable backend', async () => {
    PathorsCallsAPI.join.mockResolvedValue({ serverUrl: 'wss://x' });
    const { join, error, isJoined } = usePathorsCallSession();

    const joined = await join({ accountId: 3, callId: 42 });

    expect(joined).toBe(false);
    expect(error.value).toBe(PATHORS_JOIN_ERROR.UNAVAILABLE);
    expect(isJoined.value).toBe(false);
  });

  it('reports a denied microphone distinctly', async () => {
    PathorsCallsAPI.join.mockResolvedValue(credentials);
    micState.nextError = Object.assign(new Error('denied'), {
      name: 'NotAllowedError',
    });
    const { join, error, isJoined } = usePathorsCallSession();

    const joined = await join({ accountId: 3, callId: 42 });

    expect(joined).toBe(false);
    expect(error.value).toBe(PATHORS_JOIN_ERROR.MEDIA_DENIED);
    expect(isJoined.value).toBe(false);
    expect(rooms[0].disconnect).toHaveBeenCalled();
  });

  describe('hangup', () => {
    const joinCall = async () => {
      PathorsCallsAPI.join.mockResolvedValue(credentials);
      const session = usePathorsCallSession();
      await session.join({ accountId: 3, callId: 42 });
      return session;
    };

    it('asks the backend to end the call and tears down locally', async () => {
      PathorsCallsAPI.hangup.mockResolvedValue({ ok: true });
      const { hangup, isJoined, isHangingUp, isActiveCall, error } =
        await joinCall();

      const ended = await hangup({ accountId: 3 });

      expect(ended).toBe(true);
      expect(PathorsCallsAPI.hangup).toHaveBeenCalledWith(42, 3);
      expect(rooms[0].disconnect).toHaveBeenCalled();
      expect(isJoined.value).toBe(false);
      expect(isHangingUp.value).toBe(false);
      expect(isActiveCall(42)).toBe(false);
      expect(error.value).toBeNull();
    });

    it.each([404, 410])(
      'treats a %i as an already-ended call and tears down',
      async status => {
        PathorsCallsAPI.hangup.mockImplementation(() => rejectWith(status));
        const { hangup, isJoined, error } = await joinCall();

        const ended = await hangup({ accountId: 3 });

        expect(ended).toBe(true);
        expect(rooms[0].disconnect).toHaveBeenCalled();
        expect(isJoined.value).toBe(false);
        expect(error.value).toBeNull();
      }
    );

    it.each([409, 502])(
      'keeps the agent in the call on a %i and reports the failure',
      async status => {
        PathorsCallsAPI.hangup.mockImplementation(() => rejectWith(status));
        const { hangup, isJoined, isHangingUp, isActiveCall, error } =
          await joinCall();

        const ended = await hangup({ accountId: 3 });

        expect(ended).toBe(false);
        expect(rooms[0].disconnect).not.toHaveBeenCalled();
        expect(isJoined.value).toBe(true);
        expect(isActiveCall(42)).toBe(true);
        expect(isHangingUp.value).toBe(false);
        expect(error.value).toBe(PATHORS_JOIN_ERROR.HANGUP_FAILED);
      }
    );

    it('keeps the agent in the call on a network error', async () => {
      PathorsCallsAPI.hangup.mockRejectedValue(new Error('Network Error'));
      const { hangup, isJoined, error } = await joinCall();

      const ended = await hangup({ accountId: 3 });

      expect(ended).toBe(false);
      expect(isJoined.value).toBe(true);
      expect(error.value).toBe(PATHORS_JOIN_ERROR.HANGUP_FAILED);
    });

    it('ignores a second click while the first hangup is in flight', async () => {
      let resolveHangup;
      PathorsCallsAPI.hangup.mockImplementation(
        () =>
          new Promise(resolve => {
            resolveHangup = resolve;
          })
      );
      const { hangup, isHangingUp } = await joinCall();

      const first = hangup({ accountId: 3 });
      expect(isHangingUp.value).toBe(true);
      const second = await hangup({ accountId: 3 });

      expect(second).toBe(false);
      expect(PathorsCallsAPI.hangup).toHaveBeenCalledTimes(1);

      resolveHangup({ ok: true });
      await expect(first).resolves.toBe(true);
      expect(isHangingUp.value).toBe(false);
    });

    it('is a no-op when not in a call', async () => {
      const { hangup } = usePathorsCallSession();

      const ended = await hangup({ accountId: 3 });

      expect(ended).toBe(false);
      expect(PathorsCallsAPI.hangup).not.toHaveBeenCalled();
    });

    it('does not touch a newer session when the room dropped mid-request', async () => {
      let rejectHangup;
      PathorsCallsAPI.hangup.mockImplementation(
        () =>
          new Promise((_, reject) => {
            rejectHangup = reject;
          })
      );
      const first = await joinCall();
      const pending = first.hangup({ accountId: 3 });

      // The backend tore the room down before answering, and the agent has
      // already joined another call by the time the (failed) answer lands.
      rooms[0].emit(ROOM_EVENT.Disconnected);
      PathorsCallsAPI.join.mockResolvedValue(credentials);
      await first.join({ accountId: 3, callId: 99 });
      const failure = new Error('Request failed with status 502');
      failure.response = { status: 502 };
      rejectHangup(failure);

      await expect(pending).resolves.toBe(true);
      expect(first.isJoined.value).toBe(true);
      expect(first.isActiveCall(99)).toBe(true);
      expect(first.error.value).toBeNull();
      expect(rooms[1].disconnect).not.toHaveBeenCalled();
    });
  });

  describe('audio playback unlock', () => {
    const joinCall = async () => {
      PathorsCallsAPI.join.mockResolvedValue(credentials);
      const session = usePathorsCallSession();
      await session.join({ accountId: 3, callId: 42 });
      return session;
    };

    const audioTrack = element => ({
      kind: 'audio',
      attach: () => element,
      detach: () => [element],
    });

    beforeEach(() => {
      vi.spyOn(console, 'warn').mockImplementation(() => {});
    });

    it('tries to start room audio right after connecting', async () => {
      const { isAudioBlocked } = await joinCall();

      expect(rooms[0].startAudio).toHaveBeenCalled();
      expect(isAudioBlocked.value).toBe(false);
    });

    it('flags audio as blocked when startAudio rejects without a gesture', async () => {
      micState.nextAudioBlocked = true;
      const { isAudioBlocked, isJoined } = await joinCall();

      expect(rooms[0].startAudio).toHaveBeenCalled();
      expect(isJoined.value).toBe(true);
      expect(isAudioBlocked.value).toBe(true);
    });

    it('mirrors AudioPlaybackStatusChanged into isAudioBlocked', async () => {
      const { isAudioBlocked } = await joinCall();

      rooms[0].canPlaybackAudio = false;
      rooms[0].emit(ROOM_EVENT.AudioPlaybackStatusChanged, false);
      expect(isAudioBlocked.value).toBe(true);

      rooms[0].canPlaybackAudio = true;
      rooms[0].emit(ROOM_EVENT.AudioPlaybackStatusChanged, true);
      expect(isAudioBlocked.value).toBe(false);
    });

    it('flags audio as blocked when an attached track cannot play', async () => {
      const { isAudioBlocked } = await joinCall();
      const element = document.createElement('audio');
      element.play = vi
        .fn()
        .mockRejectedValue(
          Object.assign(new Error('blocked'), { name: 'NotAllowedError' })
        );

      expect(() =>
        rooms[0].emit(ROOM_EVENT.TrackSubscribed, audioTrack(element))
      ).not.toThrow();
      await vi.waitFor(() => expect(isAudioBlocked.value).toBe(true));
    });

    it('enableAudio starts room audio, replays elements and clears the flag', async () => {
      const { isAudioBlocked, enableAudio } = await joinCall();
      const element = document.createElement('audio');
      element.play = vi.fn().mockRejectedValueOnce(new Error('blocked'));
      rooms[0].canPlaybackAudio = false;
      rooms[0].emit(ROOM_EVENT.TrackSubscribed, audioTrack(element));
      await vi.waitFor(() => expect(isAudioBlocked.value).toBe(true));

      rooms[0].startAudio.mockImplementation(async () => {
        rooms[0].canPlaybackAudio = true;
      });
      element.play.mockResolvedValue(undefined);
      await enableAudio();

      expect(rooms[0].startAudio).toHaveBeenCalledTimes(2);
      expect(element.play).toHaveBeenCalledTimes(2);
      expect(isAudioBlocked.value).toBe(false);
    });

    it('keeps the flag set when enableAudio fails', async () => {
      const { isAudioBlocked, enableAudio } = await joinCall();
      rooms[0].canPlaybackAudio = false;
      rooms[0].emit(ROOM_EVENT.AudioPlaybackStatusChanged, false);
      rooms[0].startAudio.mockRejectedValue(new Error('still blocked'));

      await expect(enableAudio()).resolves.toBeUndefined();
      expect(isAudioBlocked.value).toBe(true);
    });

    it('is a no-op when not in a call', async () => {
      const { enableAudio, isAudioBlocked } = usePathorsCallSession();

      await expect(enableAudio()).resolves.toBeUndefined();
      expect(isAudioBlocked.value).toBe(false);
    });

    it('clears the flag on hangup and on a remote disconnect', async () => {
      PathorsCallsAPI.hangup.mockResolvedValue({ ok: true });
      const first = await joinCall();
      rooms[0].canPlaybackAudio = false;
      rooms[0].emit(ROOM_EVENT.AudioPlaybackStatusChanged, false);
      expect(first.isAudioBlocked.value).toBe(true);

      await first.hangup({ accountId: 3 });
      expect(first.isAudioBlocked.value).toBe(false);

      const second = await joinCall();
      rooms[1].canPlaybackAudio = false;
      rooms[1].emit(ROOM_EVENT.AudioPlaybackStatusChanged, false);
      expect(second.isAudioBlocked.value).toBe(true);

      rooms[1].emit(ROOM_EVENT.Disconnected);
      expect(second.isAudioBlocked.value).toBe(false);
    });
  });
});
