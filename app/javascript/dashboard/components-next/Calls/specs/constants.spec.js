import { CALL_STATE } from 'dashboard/helper/pathorsCallState';
import { callSection, dateRangeParams, mergeLiveCall } from '../constants';

// TZ=UTC in the test script, so local day boundaries are UTC midnights.
const NOW = new Date('2026-10-11T15:30:00Z');
const MIDNIGHT = Date.parse('2026-10-11T00:00:00Z') / 1000;
const DAY = 86_400;

describe('dateRangeParams', () => {
  it('turns a preset into since/until epoch seconds in the local day', () => {
    expect(dateRangeParams('today', NOW)).toEqual({ since: MIDNIGHT });
    expect(dateRangeParams('yesterday', NOW)).toEqual({
      since: MIDNIGHT - DAY,
      until: MIDNIGHT,
    });
    expect(dateRangeParams('7d', NOW)).toEqual({ since: MIDNIGHT - 6 * DAY });
    expect(dateRangeParams(null, NOW)).toEqual({});
  });
});

describe('callSection', () => {
  beforeEach(() => {
    vi.useFakeTimers({ now: NOW, toFake: ['Date'] });
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  const ended = { status: 'completed' };

  it('puts calls needing a human first, live calls next', () => {
    expect(
      callSection({ status: 'in-progress' }, { key: CALL_STATE.REQUESTED })
    ).toBe('need');
    expect(
      callSection({ ...ended, followUp: true }, { key: CALL_STATE.ENDED })
    ).toBe('need');
    expect(callSection({ status: 'in-progress' }, { key: CALL_STATE.AI })).toBe(
      'live'
    );
  });

  it('files ended calls by the day they started', () => {
    const at = seconds => ({ ...ended, startedAt: seconds });
    const state = { key: CALL_STATE.ENDED };
    expect(callSection(at(MIDNIGHT + 60), state)).toBe('today');
    expect(callSection(at(MIDNIGHT - 60), state)).toBe('yesterday');
    expect(callSection(at(MIDNIGHT - 3 * DAY), state)).toBe('earlier');
  });
});

describe('mergeLiveCall', () => {
  it('lets the live store override what the list fetched earlier', () => {
    const row = {
      id: 1,
      status: 'in-progress',
      needsAction: false,
      agent: { id: 3 },
      live: { seq: 1 },
    };
    const record = { needsAction: true, acceptedByAgentId: null };

    expect(mergeLiveCall(row, record, { seq: 4 })).toMatchObject({
      needsAction: true,
      acceptedByAgentId: null,
      agent: { id: 3 },
      live: { seq: 4 },
    });
    expect(mergeLiveCall(row, undefined, undefined).live).toEqual({ seq: 1 });
  });
});
