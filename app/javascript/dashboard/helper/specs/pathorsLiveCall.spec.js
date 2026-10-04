import {
  PATHORS_ALERT_LEVEL,
  PATHORS_ALERT_THRESHOLDS,
  PATHORS_ALERT_TYPE,
  callElapsedSeconds,
  getPathorsCallAlerts,
  highestAlertLevel,
  isAiHandlingCall,
  sortLiveCalls,
} from '../pathorsLiveCall';

const NOW = Date.parse('2026-10-04T10:00:00Z');
const secondsAgo = seconds => new Date(NOW - seconds * 1000).toISOString();

const aiCall = (live = {}, overrides = {}) => ({
  status: 'in-progress',
  acceptedByAgentId: null,
  live: { turns: 0, interruptions: 0, transferFailed: false, ...live },
  ...overrides,
});

const types = alerts => alerts.map(alert => alert.type);

describe('callElapsedSeconds', () => {
  it('counts whole seconds since the start', () => {
    expect(callElapsedSeconds(secondsAgo(75.6), NOW)).toBe(75);
  });

  it('is zero without a usable start or for a start in the future', () => {
    expect(callElapsedSeconds(null, NOW)).toBe(0);
    expect(callElapsedSeconds('not a date', NOW)).toBe(0);
    expect(callElapsedSeconds(secondsAgo(-30), NOW)).toBe(0);
  });
});

describe('isAiHandlingCall', () => {
  it('is true while the call rings or is in progress with nobody on it', () => {
    expect(isAiHandlingCall({ status: 'ringing' })).toBe(true);
    expect(isAiHandlingCall({ status: 'in-progress' })).toBe(true);
  });

  it('is false once an agent took over or the call ended', () => {
    expect(
      isAiHandlingCall({ status: 'in-progress', acceptedByAgentId: 7 })
    ).toBe(false);
    expect(isAiHandlingCall({ status: 'completed' })).toBe(false);
  });
});

describe('getPathorsCallAlerts', () => {
  it('raises nothing for a calm call', () => {
    expect(getPathorsCallAlerts(aiCall({ turns: 4 }), 60)).toEqual([]);
  });

  it('flags a failed transfer as red', () => {
    const [alert] = getPathorsCallAlerts(aiCall({ transferFailed: true }), 10);

    expect(alert).toMatchObject({
      type: PATHORS_ALERT_TYPE.TRANSFER_FAILED,
      level: PATHORS_ALERT_LEVEL.RED,
      labelKey: 'CONVERSATION.VOICE_CALL.LIVE.ALERTS.TRANSFER_FAILED',
      hintKey: 'CONVERSATION.VOICE_CALL.LIVE.ALERTS.TRANSFER_FAILED_HINT',
    });
  });

  it('flags each threshold only once it is exceeded', () => {
    const atThresholds = aiCall({
      interruptions: PATHORS_ALERT_THRESHOLDS.INTERRUPTIONS,
      turns: PATHORS_ALERT_THRESHOLDS.TURNS,
    });
    expect(
      getPathorsCallAlerts(
        atThresholds,
        PATHORS_ALERT_THRESHOLDS.DURATION_SECONDS
      )
    ).toEqual([]);

    const overThresholds = aiCall({
      interruptions: PATHORS_ALERT_THRESHOLDS.INTERRUPTIONS + 1,
      turns: PATHORS_ALERT_THRESHOLDS.TURNS + 1,
    });
    const alerts = getPathorsCallAlerts(
      overThresholds,
      PATHORS_ALERT_THRESHOLDS.DURATION_SECONDS + 1
    );
    expect(types(alerts)).toEqual([
      PATHORS_ALERT_TYPE.INTERRUPTIONS,
      PATHORS_ALERT_TYPE.LONG_CALL,
      PATHORS_ALERT_TYPE.MANY_TURNS,
    ]);
    expect(
      alerts.every(alert => alert.level === PATHORS_ALERT_LEVEL.AMBER)
    ).toBe(true);
  });

  it('passes the numbers the chip text needs', () => {
    const alerts = getPathorsCallAlerts(
      aiCall({ interruptions: 6, turns: 25 }),
      400
    );

    expect(alerts.map(alert => alert.params)).toEqual([
      { count: 6 },
      { minutes: 5 },
      { count: 20 },
    ]);
  });

  it('still times a call that has no live state yet', () => {
    const alerts = getPathorsCallAlerts({ status: 'ringing', live: null }, 301);

    expect(types(alerts)).toEqual([PATHORS_ALERT_TYPE.LONG_CALL]);
  });

  it('stays quiet after an agent took over or the call ended', () => {
    const noisy = { transferFailed: true, interruptions: 9, turns: 40 };

    expect(
      getPathorsCallAlerts(aiCall(noisy, { acceptedByAgentId: 3 }), 900)
    ).toEqual([]);
    expect(
      getPathorsCallAlerts(aiCall(noisy, { status: 'completed' }), 900)
    ).toEqual([]);
  });
});

describe('highestAlertLevel', () => {
  it('picks red over amber and null without alerts', () => {
    expect(highestAlertLevel([])).toBeNull();
    expect(highestAlertLevel([{ level: 'amber' }])).toBe('amber');
    expect(highestAlertLevel([{ level: 'amber' }, { level: 'red' }])).toBe(
      'red'
    );
  });
});

describe('sortLiveCalls', () => {
  it('orders by severity, then by how long the call has run', () => {
    const calm = { id: 1, ...aiCall(), startedAt: secondsAgo(200) };
    const calmer = { id: 2, ...aiCall(), startedAt: secondsAgo(30) };
    const amber = {
      id: 3,
      ...aiCall({ interruptions: 5 }),
      startedAt: secondsAgo(10),
    };
    const red = {
      id: 4,
      ...aiCall({ transferFailed: true }),
      startedAt: secondsAgo(5),
    };
    const takenOver = {
      id: 5,
      ...aiCall({ transferFailed: true }, { acceptedByAgentId: 9 }),
      startedAt: secondsAgo(600),
    };

    const sorted = sortLiveCalls([calmer, takenOver, amber, calm, red], NOW);

    expect(sorted.map(call => call.id)).toEqual([4, 3, 5, 1, 2]);
  });
});
