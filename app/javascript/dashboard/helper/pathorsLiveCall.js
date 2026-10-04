import { VOICE_CALL_STATUS } from 'dashboard/components-next/message/constants';

/**
 * Reading a live Pathors call while the AI is handling it: how long it has
 * been on the line, and which warning signs say a human should step in.
 *
 * `live` is what the Pathors backend pushes on every AI turn (camelized):
 * `{ seq, turns, interruptions, transferFailed, transcript, updatedAt }`.
 * Alerts are computed here, from `live` plus the clock, so the bubble and the
 * conversation list can never disagree about them.
 */

// A call is over the line once it goes past these, not when it reaches them.
export const PATHORS_ALERT_THRESHOLDS = Object.freeze({
  INTERRUPTIONS: 3,
  DURATION_SECONDS: 300,
  TURNS: 20,
});

export const PATHORS_ALERT_LEVEL = Object.freeze({
  RED: 'red',
  AMBER: 'amber',
});

export const PATHORS_ALERT_TYPE = Object.freeze({
  TRANSFER_FAILED: 'transfer_failed',
  INTERRUPTIONS: 'interruptions',
  LONG_CALL: 'long_call',
  MANY_TURNS: 'many_turns',
});

const SEVERITY_RANK = {
  [PATHORS_ALERT_LEVEL.RED]: 2,
  [PATHORS_ALERT_LEVEL.AMBER]: 1,
};

const SECONDS_PER_MINUTE = 60;
const MS_PER_SECOND = 1000;

const ACTIVE_STATUSES = [
  VOICE_CALL_STATUS.RINGING,
  VOICE_CALL_STATUS.IN_PROGRESS,
];

const I18N_PREFIX = 'CONVERSATION.VOICE_CALL.LIVE.ALERTS';

/**
 * @param {string|number|null|undefined} startedAt ISO-8601 string or epoch ms
 * @param {number} now epoch ms
 * @returns {number} whole seconds since the call started, never negative
 */
export const callElapsedSeconds = (startedAt, now) => {
  if (!startedAt) return 0;
  const started = new Date(startedAt).getTime();
  if (Number.isNaN(started)) return 0;
  return Math.max(0, Math.floor((now - started) / MS_PER_SECOND));
};

/**
 * The call is still on the line (display status: ringing or in-progress).
 * @param {string|undefined} status
 */
export const isLiveCallStatus = status => ACTIVE_STATUSES.includes(status);

/**
 * The AI is still on the call: it has not ended and nobody has taken it over.
 * Taking a call over is final (there is no handing it back), so a recorded
 * answering agent means the AI is done.
 * @param {{ status?: string, acceptedByAgentId?: number|null }} call
 */
export const isAiHandlingCall = call =>
  isLiveCallStatus(call?.status) && !call?.acceptedByAgentId;

/**
 * @typedef {Object} PathorsCallAlert
 * @property {string} type - one of PATHORS_ALERT_TYPE
 * @property {string} level - one of PATHORS_ALERT_LEVEL
 * @property {string} labelKey - i18n key for the short chip text
 * @property {string} hintKey - i18n key for the banner explanation
 * @property {Object} params - i18n params for both keys
 */

/**
 * @param {{ status?: string, acceptedByAgentId?: number|null, live?: Object|null }} call
 * @param {number} elapsedSeconds
 * @returns {PathorsCallAlert[]} red alerts first; empty unless the AI is handling the call
 */
export const getPathorsCallAlerts = (call, elapsedSeconds) => {
  if (!isAiHandlingCall(call)) return [];

  const live = call.live || {};
  const alerts = [];
  const add = (type, level, key, params = {}) =>
    alerts.push({
      type,
      level,
      labelKey: `${I18N_PREFIX}.${key}`,
      hintKey: `${I18N_PREFIX}.${key}_HINT`,
      params,
    });

  if (live.transferFailed) {
    add(
      PATHORS_ALERT_TYPE.TRANSFER_FAILED,
      PATHORS_ALERT_LEVEL.RED,
      'TRANSFER_FAILED'
    );
  }
  if ((live.interruptions || 0) > PATHORS_ALERT_THRESHOLDS.INTERRUPTIONS) {
    add(
      PATHORS_ALERT_TYPE.INTERRUPTIONS,
      PATHORS_ALERT_LEVEL.AMBER,
      'INTERRUPTIONS',
      { count: live.interruptions }
    );
  }
  if (elapsedSeconds > PATHORS_ALERT_THRESHOLDS.DURATION_SECONDS) {
    add(PATHORS_ALERT_TYPE.LONG_CALL, PATHORS_ALERT_LEVEL.AMBER, 'LONG_CALL', {
      minutes: PATHORS_ALERT_THRESHOLDS.DURATION_SECONDS / SECONDS_PER_MINUTE,
    });
  }
  if ((live.turns || 0) > PATHORS_ALERT_THRESHOLDS.TURNS) {
    add(
      PATHORS_ALERT_TYPE.MANY_TURNS,
      PATHORS_ALERT_LEVEL.AMBER,
      'MANY_TURNS',
      { count: PATHORS_ALERT_THRESHOLDS.TURNS }
    );
  }
  return alerts;
};

/**
 * @param {PathorsCallAlert[]} alerts
 * @returns {string|null} the most severe level, or null without alerts
 */
export const highestAlertLevel = alerts =>
  alerts.reduce(
    (highest, alert) =>
      (SEVERITY_RANK[alert.level] || 0) > (SEVERITY_RANK[highest] || 0)
        ? alert.level
        : highest,
    null
  );

/**
 * Most severe first, then the longest-running.
 * @param {Array<{ status?: string, acceptedByAgentId?: number|null, live?: Object|null, startedAt?: string }>} calls
 * @param {number} now epoch ms
 * @returns {Array} a sorted copy
 */
export const sortLiveCalls = (calls, now) => {
  const rank = call => {
    const elapsed = callElapsedSeconds(call.startedAt, now);
    const level = highestAlertLevel(getPathorsCallAlerts(call, elapsed));
    return { severity: SEVERITY_RANK[level] || 0, elapsed };
  };
  return calls
    .map(call => ({ call, ...rank(call) }))
    .sort((a, b) => b.severity - a.severity || b.elapsed - a.elapsed)
    .map(({ call }) => call);
};
