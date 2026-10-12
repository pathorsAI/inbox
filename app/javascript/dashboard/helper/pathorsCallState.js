import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';
import {
  PATHORS_ALERT_LEVEL,
  callElapsedSeconds,
  getPathorsCallAlerts,
  isLiveCallStatus,
} from 'dashboard/helper/pathorsLiveCall';

/**
 * The one answer to "what is going on with this call, and can I take it over?"
 * for every surface that shows a Pathors call: the calls table, the detail
 * sheet, the attention stack and the voice_call bubble.
 *
 * The input is a camelized call from any of the three sources (the calls list,
 * the live store, a voice_call message), with its `live` state attached.
 * `needsAction` is decided by the server (Pathors::CallLifecycleService); the
 * attention block only tells *why* a human is needed.
 */

export const CALL_STATE = Object.freeze({
  ENDED: 'ended',
  TRANSFERRED: 'transferred',
  DIALING: 'dialing',
  HUMAN: 'human',
  REQUESTED: 'requested',
  TRANSFER_FAILED: 'transfer_failed',
  WARN: 'warn',
  AI: 'ai',
  // A live Twilio / WhatsApp call: no AI on it, nothing to take over here.
  LIVE: 'live',
});

export const CALL_TONE = Object.freeze({
  RUBY: 'ruby',
  AMBER: 'amber',
  BLUE: 'blue',
  SLATE: 'slate',
  TEAL: 'teal',
});

export const CALL_OUTCOMES = Object.freeze([
  'ai_done',
  'transferred',
  'human',
  'transfer_failed',
  'hangup',
  'no_answer',
]);

export const TAKEOVER_REASONS = Object.freeze([
  'looping',
  'customer_confused',
  'cannot_hear',
  'wants_human_no_target',
  'out_of_scope',
  'other',
]);

// What the agent reports when a transfer did not connect (pathors
// `TRANSFER_FAILURE_REASONS`).
export const TRANSFER_FAILURE_REASONS = Object.freeze([
  'no_answer',
  'busy',
  'timeout',
  'caller_hung_up',
  'no_trunk',
  'error',
]);

const TRANSFER_PHASE = { DIALING: 'dialing', CONNECTED: 'connected' };
const FAILED_PHASE = 'failed';
const I18N = 'CALLS_PAGE';
const MS_PER_SECOND = 1000;
// Epoch seconds stay below this until the year 33658; epoch ms passed it in 1973.
const EPOCH_MS_THRESHOLD = 1e12;

/**
 * The calls list sends epoch seconds, the live endpoints ISO-8601 strings and
 * the backend's own attention timestamps epoch ms; everything below compares
 * epoch ms.
 * @param {string|number|null|undefined} value
 * @returns {number|null}
 */
export const toEpochMs = value => {
  if (value === null || value === undefined || value === '') return null;
  if (typeof value === 'number') {
    return value < EPOCH_MS_THRESHOLD ? value * MS_PER_SECOND : value;
  }
  const parsed = Date.parse(value);
  return Number.isNaN(parsed) ? null : parsed;
};

export const takeoverReasonKey = reason =>
  `${I18N}.REASON.${(TAKEOVER_REASONS.includes(reason) ? reason : 'other').toUpperCase()}`;

/** i18n key for a transfer failure reason, or null when none (or unknown) was reported. */
export const transferFailureReasonKey = reason =>
  TRANSFER_FAILURE_REASONS.includes(reason)
    ? `${I18N}.TRANSFER_FAILURE.${reason.toUpperCase()}`
    : null;

export const outcomeLabelKey = outcome =>
  CALL_OUTCOMES.includes(outcome)
    ? `${I18N}.OUTCOME.${outcome.toUpperCase()}`
    : `${I18N}.STATE.ENDED`;

const attentionOf = call => call.live?.attention || {};

const unansweredSince = (call, at) => {
  const acceptedAt = toEpochMs(call.acceptedAt);
  return !acceptedAt || acceptedAt < at;
};

const isRequestOpen = call => {
  const request = attentionOf(call).takeoverRequest;
  return !!request && unansweredSince(call, request.at);
};

// Backends that predate `attention` only send `transferFailed`, with no time;
// any join answers it.
const isFailedTransferOpen = call => {
  const { transfer } = attentionOf(call);
  if (transfer) {
    return (
      transfer.phase === FAILED_PHASE && unansweredSince(call, transfer.at)
    );
  }
  return !!call.live?.transferFailed && !call.acceptedAt;
};

// The live sources carry the id; the calls list nests the agent instead. A
// live `null` (the human left) must win over a stale list agent.
const agentIdOf = call =>
  call.acceptedByAgentId === undefined
    ? (call.agent?.id ?? null)
    : call.acceptedByAgentId;

// An ended call still owed a callback says so first; its outcome becomes the
// secondary detail (`outcomeKey`) rather than a red "AI 完成".
const endedState = call => ({
  key: CALL_STATE.ENDED,
  tone: call.followUp ? CALL_TONE.RUBY : CALL_TONE.SLATE,
  labelKey: call.followUp
    ? `${I18N}.CHIPS.FOLLOW_UP`
    : outcomeLabelKey(call.outcome),
  outcomeKey: outcomeLabelKey(call.outcome),
  detail: '',
  canJoin: false,
});

const requestedState = call => {
  const request = attentionOf(call).takeoverRequest || {};
  return {
    key: CALL_STATE.REQUESTED,
    tone: CALL_TONE.RUBY,
    labelKey: `${I18N}.STATE.REQUESTED`,
    reasonKey: takeoverReasonKey(request.reason),
    detail: request.detail || '',
    at: request.at ?? null,
    canJoin: true,
  };
};

const transferFailedState = call => {
  const transfer = attentionOf(call).transfer || {};
  return {
    key: CALL_STATE.TRANSFER_FAILED,
    tone: CALL_TONE.RUBY,
    labelKey: `${I18N}.STATE.TRANSFER_FAILED`,
    target: transfer.targetMasked || '',
    reasonKey: transferFailureReasonKey(transfer.failureReason),
    detail: '',
    at: transfer.at ?? null,
    canJoin: true,
  };
};

// Which of the two reasons a human is needed. The server already decided that
// one is (`needsAction`); when the client's `acceptedAt` is stale neither
// signal looks open, so the one that exists wins.
const needsActionState = call => {
  if (isRequestOpen(call)) return requestedState(call);
  if (isFailedTransferOpen(call)) return transferFailedState(call);
  return attentionOf(call).takeoverRequest
    ? requestedState(call)
    : transferFailedState(call);
};

const humanState = (call, currentUserId) => {
  const isMine = agentIdOf(call) === currentUserId;
  return {
    key: CALL_STATE.HUMAN,
    tone: CALL_TONE.BLUE,
    labelKey: isMine ? `${I18N}.STATE.HUMAN_ME` : `${I18N}.STATE.HUMAN`,
    labelParams: { name: call.acceptedByAgentName || call.agent?.name || '' },
    detail: '',
    isMine,
    // The agent holding the call may get back in after a dropped connection.
    canJoin: isMine,
  };
};

const aiState = (call, now) => {
  const elapsed = callElapsedSeconds(toEpochMs(call.startedAt), now);
  const alerts = getPathorsCallAlerts(
    { ...call, acceptedByAgentId: null },
    elapsed
  ).filter(alert => alert.level === PATHORS_ALERT_LEVEL.AMBER);
  return {
    key: alerts.length ? CALL_STATE.WARN : CALL_STATE.AI,
    tone: alerts.length ? CALL_TONE.AMBER : CALL_TONE.TEAL,
    labelKey: `${I18N}.STATE.AI`,
    alerts,
    detail: '',
    canJoin: true,
  };
};

/**
 * @param {Object} call camelized call with `live` attached
 * @param {{ now?: number, currentUserId?: number|null }} [options]
 * @returns {{ key: string, tone: string, labelKey: string, labelParams?: Object,
 *   detail: string, canJoin: boolean, joinDisabledReasonKey?: string,
 *   reasonKey?: string, target?: string, at?: number|null, alerts?: Array,
 *   isMine?: boolean }}
 */
export const primaryCallState = (
  call,
  { now = Date.now(), currentUserId = null } = {}
) => {
  if (!isLiveCallStatus(call.status)) return endedState(call);

  if (call.provider && call.provider !== VOICE_CALL_PROVIDERS.PATHORS) {
    return agentIdOf(call)
      ? { ...humanState(call, currentUserId), canJoin: false }
      : {
          key: CALL_STATE.LIVE,
          tone: CALL_TONE.TEAL,
          labelKey: `${I18N}.STATE.LIVE`,
          detail: '',
          canJoin: false,
        };
  }

  const { transfer } = attentionOf(call);
  if (transfer?.phase === TRANSFER_PHASE.CONNECTED) {
    return {
      key: CALL_STATE.TRANSFERRED,
      tone: CALL_TONE.SLATE,
      labelKey: `${I18N}.STATE.TRANSFERRED`,
      target: transfer.targetMasked || '',
      detail: '',
      canJoin: false,
    };
  }
  if (transfer?.phase === TRANSFER_PHASE.DIALING) {
    return {
      key: CALL_STATE.DIALING,
      tone: CALL_TONE.BLUE,
      labelKey: `${I18N}.STATE.DIALING`,
      target: transfer.targetMasked || '',
      detail: '',
      canJoin: false,
      joinDisabledReasonKey: `${I18N}.STATE.DIALING_NO_JOIN`,
    };
  }
  if (agentIdOf(call)) return humanState(call, currentUserId);

  const needsAction =
    call.needsAction ?? (isRequestOpen(call) || isFailedTransferOpen(call));
  if (needsAction) return needsActionState(call);

  return aiState(call, now);
};

/**
 * Whether the AI ever asked for help on this call, answered or not — a
 * secondary chip once the call has moved on.
 */
export const hasRequestedHelp = call =>
  !!call.takeoverRequested || !!attentionOf(call).takeoverRequest;

/**
 * Whole minutes since an epoch-ms instant, never negative.
 * @param {number|null|undefined} atMs
 * @param {number} now
 */
export const minutesSince = (atMs, now) =>
  atMs ? Math.max(0, Math.floor((now - atMs) / (60 * MS_PER_SECOND))) : 0;
