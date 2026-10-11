import {
  CALL_STATE,
  CALL_TONE,
  hasRequestedHelp,
  minutesSince,
  outcomeLabelKey,
  primaryCallState,
  takeoverReasonKey,
  toEpochMs,
} from '../pathorsCallState';

const NOW = Date.parse('2026-10-11T10:00:00Z');
const ME = 7;

const liveCall = (overrides = {}, live = {}) => ({
  id: 1,
  provider: 'pathors',
  status: 'in-progress',
  startedAt: new Date(NOW - 60_000).toISOString(),
  acceptedByAgentId: null,
  acceptedAt: null,
  needsAction: false,
  live: { turns: 2, interruptions: 0, transferFailed: false, ...live },
  ...overrides,
});

const request = (at = NOW - 120_000) => ({
  takeoverRequest: {
    reason: 'looping',
    detail: 'asked the same thing three times',
    source: 'ai',
    at,
  },
  transfer: null,
  humanLeftAt: null,
});

const transfer = (phase, extra = {}) => ({
  takeoverRequest: null,
  transfer: { phase, targetMasked: '****5678', at: NOW - 30_000, ...extra },
  humanLeftAt: null,
});

const stateOf = call => primaryCallState(call, { now: NOW, currentUserId: ME });

describe('primaryCallState', () => {
  it('reads an ended call as its outcome, ruby while a call-back is owed', () => {
    expect(
      stateOf(liveCall({ status: 'completed', outcome: 'ai_done' }))
    ).toMatchObject({
      key: CALL_STATE.ENDED,
      tone: CALL_TONE.SLATE,
      labelKey: 'CALLS_PAGE.OUTCOME.AI_DONE',
      canJoin: false,
    });
    expect(
      stateOf(
        liveCall({
          status: 'completed',
          outcome: 'transfer_failed',
          followUp: true,
        })
      )
    ).toMatchObject({
      tone: CALL_TONE.RUBY,
      labelKey: 'CALLS_PAGE.CHIPS.FOLLOW_UP',
      outcomeKey: 'CALLS_PAGE.OUTCOME.TRANSFER_FAILED',
    });
  });

  it('falls back to a plain ended label without an outcome', () => {
    expect(stateOf(liveCall({ status: 'no-answer' })).labelKey).toBe(
      'CALLS_PAGE.STATE.ENDED'
    );
  });

  it('puts a connected transfer above everything else and blocks take-over', () => {
    const state = stateOf(
      liveCall(
        { needsAction: true, acceptedByAgentId: 3 },
        { attention: transfer('connected') }
      )
    );
    expect(state).toMatchObject({
      key: CALL_STATE.TRANSFERRED,
      target: '****5678',
      canJoin: false,
    });
  });

  it('disables take-over while the transfer is dialing, with a reason', () => {
    expect(
      stateOf(liveCall({}, { attention: transfer('dialing') }))
    ).toMatchObject({
      key: CALL_STATE.DIALING,
      tone: CALL_TONE.BLUE,
      canJoin: false,
      joinDisabledReasonKey: 'CALLS_PAGE.STATE.DIALING_NO_JOIN',
    });
  });

  it('names the agent on the call, and lets only that agent back in', () => {
    const other = stateOf(
      liveCall({ acceptedByAgentId: 3, acceptedByAgentName: 'Amy' })
    );
    expect(other).toMatchObject({
      key: CALL_STATE.HUMAN,
      labelKey: 'CALLS_PAGE.STATE.HUMAN',
      labelParams: { name: 'Amy' },
      canJoin: false,
      isMine: false,
    });

    const mine = stateOf(liveCall({ acceptedByAgentId: ME }));
    expect(mine).toMatchObject({
      labelKey: 'CALLS_PAGE.STATE.HUMAN_ME',
      canJoin: true,
      isMine: true,
    });
  });

  it('reads the list shape, whose agent is nested', () => {
    expect(
      stateOf(liveCall({ acceptedByAgentId: undefined, agent: { id: ME } }))
        .isMine
    ).toBe(true);
  });

  it('reads an unanswered AI request as a request for help', () => {
    const state = stateOf(
      liveCall({ needsAction: true }, { attention: request() })
    );
    expect(state).toMatchObject({
      key: CALL_STATE.REQUESTED,
      tone: CALL_TONE.RUBY,
      reasonKey: 'CALLS_PAGE.REASON.LOOPING',
      detail: 'asked the same thing three times',
      at: NOW - 120_000,
      canJoin: true,
    });
  });

  it('reads an unanswered failed transfer as a failed transfer', () => {
    const state = stateOf(
      liveCall(
        { needsAction: true },
        {
          attention: transfer('failed', { failureReason: 'busy' }),
        }
      )
    );
    expect(state).toMatchObject({
      key: CALL_STATE.TRANSFER_FAILED,
      target: '****5678',
      reasonKey: 'CALLS_PAGE.TRANSFER_FAILURE.BUSY',
      canJoin: true,
    });
  });

  it('prefers the signal still unanswered when both exist', () => {
    const attention = {
      ...request(NOW - 300_000),
      transfer: { phase: 'failed', at: NOW - 10_000 },
    };
    const state = stateOf(
      liveCall({ needsAction: true, acceptedAt: NOW - 200_000 }, { attention })
    );
    expect(state.key).toBe(CALL_STATE.TRANSFER_FAILED);
  });

  it('counts the legacy transferFailed flag as a failed transfer', () => {
    expect(
      stateOf(liveCall({ needsAction: undefined }, { transferFailed: true }))
        .key
    ).toBe(CALL_STATE.TRANSFER_FAILED);
  });

  it('derives needsAction from the signals when the source does not carry it', () => {
    expect(
      stateOf(liveCall({ needsAction: undefined }, { attention: request() }))
        .key
    ).toBe(CALL_STATE.REQUESTED);
    expect(
      stateOf(
        liveCall(
          { needsAction: undefined, acceptedAt: NOW },
          { attention: request() }
        )
      ).key
    ).toBe(CALL_STATE.AI);
  });

  it('trusts the server when it says nothing is needed', () => {
    expect(stateOf(liveCall({}, { attention: request() })).key).toBe(
      CALL_STATE.AI
    );
  });

  it('warns in amber past the existing thresholds', () => {
    const state = stateOf(
      liveCall(
        { startedAt: new Date(NOW - 6 * 60_000).toISOString() },
        { interruptions: 4 }
      )
    );
    expect(state.key).toBe(CALL_STATE.WARN);
    expect(state.tone).toBe(CALL_TONE.AMBER);
    expect(state.alerts.map(alert => alert.type)).toEqual([
      'interruptions',
      'long_call',
    ]);
  });

  it('reads a quiet AI call as AI handling, epoch-second starts included', () => {
    expect(
      stateOf(liveCall({ startedAt: Math.floor(NOW / 1000) - 30 }))
    ).toMatchObject({
      key: CALL_STATE.AI,
      tone: CALL_TONE.TEAL,
      canJoin: true,
    });
  });

  it('never offers take-over on a live non-Pathors call', () => {
    expect(stateOf(liveCall({ provider: 'twilio' }))).toMatchObject({
      key: CALL_STATE.LIVE,
      canJoin: false,
    });
  });
});

describe('labels and helpers', () => {
  it('maps reasons and outcomes onto i18n keys, unknown reasons to other', () => {
    expect(takeoverReasonKey('cannot_hear')).toBe(
      'CALLS_PAGE.REASON.CANNOT_HEAR'
    );
    expect(takeoverReasonKey('made_up')).toBe('CALLS_PAGE.REASON.OTHER');
    expect(outcomeLabelKey('no_answer')).toBe('CALLS_PAGE.OUTCOME.NO_ANSWER');
  });

  it('normalises seconds, ms and ISO to epoch ms', () => {
    expect(toEpochMs(1_760_000_000)).toBe(1_760_000_000_000);
    expect(toEpochMs(1_760_000_000_000)).toBe(1_760_000_000_000);
    expect(toEpochMs('2026-10-11T10:00:00Z')).toBe(NOW);
    expect(toEpochMs(null)).toBeNull();
    expect(toEpochMs('nope')).toBeNull();
  });

  it('knows whether the AI ever asked for help', () => {
    expect(hasRequestedHelp({ takeoverRequested: true })).toBe(true);
    expect(hasRequestedHelp({ live: { attention: request() } })).toBe(true);
    expect(hasRequestedHelp({ live: null })).toBe(false);
  });

  it('counts whole minutes since an instant', () => {
    expect(minutesSince(NOW - 150_000, NOW)).toBe(2);
    expect(minutesSince(null, NOW)).toBe(0);
  });
});
