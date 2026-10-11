import { isToday, isYesterday, startOfDay, subDays } from 'date-fns';
import {
  CALL_STATE,
  CALL_TONE,
  toEpochMs,
} from 'dashboard/helper/pathorsCallState';
import { isLiveCallStatus } from 'dashboard/helper/pathorsLiveCall';

export const CALL_VIEWS = Object.freeze({
  NEED: 'need',
  LIVE: 'live',
  ALL: 'all',
  MINE: 'mine',
  LINE: 'line',
});

// CallFinder's `segment` values; "all" is no segment at all.
export const CALL_SEGMENTS = Object.freeze({
  NEED: 'need',
  LIVE: 'live',
  ENDED: 'ended',
});

// The views that are a segment themselves; the others let the agent pick one.
export const VIEW_SEGMENT = Object.freeze({
  [CALL_VIEWS.NEED]: CALL_SEGMENTS.NEED,
  [CALL_VIEWS.LIVE]: CALL_SEGMENTS.LIVE,
});

export const CALL_DATE_RANGES = Object.freeze(['today', 'yesterday', '7d']);

export const CALLS_PER_PAGE = 25;
export const CALLS_SEARCH_DEBOUNCE_MS = 300;
// Live updates arrive on every AI turn; the list follows them at most this often.
export const CALLS_REFRESH_DELAY_MS = 1000;

export const CALL_SECTIONS = Object.freeze([
  'need',
  'live',
  'today',
  'yesterday',
  'earlier',
]);

export const CALL_TONE_CHIP_CLASS = Object.freeze({
  [CALL_TONE.RUBY]: 'bg-n-ruby-3 text-n-ruby-11',
  [CALL_TONE.AMBER]: 'bg-n-amber-3 text-n-amber-11',
  [CALL_TONE.BLUE]: 'bg-n-blue-3 text-n-blue-11',
  [CALL_TONE.SLATE]: 'bg-n-slate-3 text-n-slate-11',
  [CALL_TONE.TEAL]: 'bg-n-teal-3 text-n-teal-11',
});

export const CALL_TONE_STRIPE_CLASS = Object.freeze({
  [CALL_TONE.RUBY]: 'bg-n-ruby-9',
  [CALL_TONE.AMBER]: 'bg-n-amber-9',
  [CALL_TONE.BLUE]: 'bg-n-blue-9',
  [CALL_TONE.SLATE]: 'bg-n-slate-5',
  [CALL_TONE.TEAL]: 'bg-n-teal-9',
});

const NEEDS_HUMAN_STATES = [CALL_STATE.REQUESTED, CALL_STATE.TRANSFER_FAILED];

const toEpochSeconds = date => Math.floor(date.getTime() / 1000);

/**
 * `since` / `until` (epoch seconds, until exclusive) for a date preset, with
 * the day boundaries in the browser's time zone.
 * @param {string|null} range one of CALL_DATE_RANGES
 * @param {Date} [now]
 * @returns {{ since?: number, until?: number }}
 */
export const dateRangeParams = (range, now = new Date()) => {
  const today = startOfDay(now);
  if (range === 'today') return { since: toEpochSeconds(today) };
  if (range === 'yesterday') {
    return {
      since: toEpochSeconds(subDays(today, 1)),
      until: toEpochSeconds(today),
    };
  }
  if (range === '7d') return { since: toEpochSeconds(subDays(today, 6)) };
  return {};
};

/**
 * Which table section a row belongs to: anything needing a human first, then
 * the calls on the line, then the rest by day.
 * @param {Object} call
 * @param {{ key: string }} state primaryCallState of the call
 */
export const callSection = (call, state) => {
  if (call.followUp || NEEDS_HUMAN_STATES.includes(state.key)) return 'need';
  if (isLiveCallStatus(call.status)) return 'live';
  const startedAt = new Date(toEpochMs(call.startedAt ?? call.createdAt));
  if (isToday(startedAt)) return 'today';
  if (isYesterday(startedAt)) return 'yesterday';
  return 'earlier';
};

// The fields a live store record knows better than a list row fetched earlier.
const LIVE_RECORD_FIELDS = [
  'status',
  'needsAction',
  'dismissed',
  'acceptedByAgentId',
  'acceptedByAgentName',
  'acceptedAt',
  'takeoverRequested',
];

/**
 * A calls-list row with what the live store has learnt since it was fetched.
 * @param {Object} row camelized calls-list row
 * @param {Object|undefined} record the pathorsLiveCalls record for the call
 * @param {Object|null|undefined} live its live state
 */
export const mergeLiveCall = (row, record, live) => {
  const merged = { ...row, live: live || row.live || null };
  if (!record) return merged;
  LIVE_RECORD_FIELDS.forEach(field => {
    if (record[field] !== undefined) merged[field] = record[field];
  });
  return merged;
};

// Calls-list rows nest the contact and inbox; live store records flatten them.
export const callerName = call => call.contact?.name || call.contactName || '';

export const callerNumber = call =>
  call.contact?.phoneNumber ||
  call.contactPhoneNumber ||
  call.fromNumber ||
  call.toNumber ||
  '';

export const lineName = call => call.inbox?.name || call.inboxName || '';
