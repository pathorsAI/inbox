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

// What the call sheet is laid out for: the AI (or nobody yet) on the line, a
// human who took it over or a transfer that connected, or a finished call.
export const CALL_SHEET_PHASE = Object.freeze({
  LIVE: 'live',
  HANDED_OFF: 'handedOff',
  ENDED: 'ended',
});

export const CALL_SHEET_TAB = Object.freeze({
  TRANSCRIPT: 'transcript',
  VARIABLES: 'variables',
  NOTES: 'notes',
  HANDOFF: 'handoff',
  SUMMARY: 'summary',
  TECHNICAL: 'technical',
});

// Each phase's tabs, the one it opens on first.
export const CALL_SHEET_TABS = Object.freeze({
  [CALL_SHEET_PHASE.LIVE]: [
    CALL_SHEET_TAB.TRANSCRIPT,
    CALL_SHEET_TAB.VARIABLES,
    CALL_SHEET_TAB.NOTES,
  ],
  [CALL_SHEET_PHASE.HANDED_OFF]: [
    CALL_SHEET_TAB.HANDOFF,
    CALL_SHEET_TAB.TRANSCRIPT,
    CALL_SHEET_TAB.NOTES,
  ],
  [CALL_SHEET_PHASE.ENDED]: [
    CALL_SHEET_TAB.SUMMARY,
    CALL_SHEET_TAB.NOTES,
    CALL_SHEET_TAB.TRANSCRIPT,
    CALL_SHEET_TAB.TECHNICAL,
  ],
});

/**
 * The sheet's phase for a call's primaryCallState.
 * @param {{ key: string }} state
 */
export const callSheetPhase = state => {
  if (state.key === CALL_STATE.ENDED) return CALL_SHEET_PHASE.ENDED;
  if ([CALL_STATE.HUMAN, CALL_STATE.TRANSFERRED].includes(state.key)) {
    return CALL_SHEET_PHASE.HANDED_OFF;
  }
  return CALL_SHEET_PHASE.LIVE;
};

// The one-click notes under a live call (CALLS_PAGE.SHEET.QUICK_TAGS.*).
export const CALL_QUICK_TAGS = Object.freeze([
  'CALL_BACK',
  'INTERESTED',
  'QUOTE',
  'COMPLAINT',
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

// Red (a human is needed) and amber (the AI is struggling) both belong in 需要處理,
// like the server's `need` segment (Call.needing_attention).
const NEED_STATES = new Set([
  CALL_STATE.REQUESTED,
  CALL_STATE.TRANSFER_FAILED,
  CALL_STATE.WARN,
]);

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
  if (call.followUp || NEED_STATES.has(state.key)) return 'need';
  if (isLiveCallStatus(call.status)) return 'live';
  const startedAt = new Date(toEpochMs(call.startedAt ?? call.createdAt));
  if (isToday(startedAt)) return 'today';
  if (isYesterday(startedAt)) return 'yesterday';
  return 'earlier';
};

const isAmber = row => row.state.tone === CALL_TONE.AMBER;

/**
 * The table's sections in CALL_SECTIONS order, empty ones left out. 需要處理
 * keeps red rows above amber ones (red is more urgent), each in list order.
 * @param {Array<{ call: Object, state: Object, section: string }>} rows
 */
export const groupCallSections = rows =>
  CALL_SECTIONS.map(key => {
    const sectionRows = rows.filter(row => row.section === key);
    return {
      key,
      rows:
        key === 'need'
          ? [
              ...sectionRows.filter(row => !isAmber(row)),
              ...sectionRows.filter(isAmber),
            ]
          : sectionRows,
    };
  }).filter(section => section.rows.length);

// The fields a live store record knows better than a list row fetched earlier.
const LIVE_RECORD_FIELDS = [
  'status',
  'needsAction',
  'dismissed',
  'acceptedByAgentId',
  'acceptedByAgentName',
  'acceptedAt',
  'takeoverRequested',
  'variables',
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

// The other party: from_number on an inbound call, to_number on an outbound
// one (from_number is then our own line) — the same rule as the backend's
// conversation attributes. The contact's own number comes first.
export const callerNumber = call => {
  const outbound = ['outbound', 'outgoing'].includes(call.direction);
  const otherParty = outbound ? call.toNumber : call.fromNumber;
  return (
    call.contact?.phoneNumber || call.contactPhoneNumber || otherParty || ''
  );
};

export const lineName = call => call.inbox?.name || call.inboxName || '';
