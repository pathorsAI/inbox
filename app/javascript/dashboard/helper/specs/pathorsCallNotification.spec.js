import {
  attentionHeadline,
  buildCallNotification,
  callNotificationTag,
  notificationPermission,
} from '../pathorsCallNotification';
import { primaryCallState } from '../pathorsCallState';

const NOW = Date.parse('2026-10-22T10:01:00Z');

const liveCall = (live = {}, overrides = {}) => ({
  id: 7,
  provider: 'pathors',
  status: 'in-progress',
  startedAt: '2026-10-22T10:00:00Z',
  acceptedByAgentId: null,
  live: { seq: 1, turns: 2, interruptions: 0, ...live },
  ...overrides,
});

const parts = overrides => ({
  callId: 7,
  accountId: 3,
  level: 'amber',
  heading: '被打斷 4 次',
  caller: '陳先生',
  number: '+886912345678',
  line: '訂位專線',
  detail: '客人一直插話，可能不耐煩',
  actionTitles: { takeOver: '前往接手', dismiss: '略過' },
  ...overrides,
});

describe('attentionHeadline', () => {
  it('names an amber call by its first alert, with that alert’s hint', () => {
    const state = primaryCallState(liveCall({ interruptions: 4 }), {
      now: NOW,
    });

    expect(attentionHeadline(state)).toEqual({
      level: 'amber',
      labelKey: 'CONVERSATION.VOICE_CALL.LIVE.ALERTS.INTERRUPTIONS',
      labelParams: { count: 4 },
      hintKey: 'CONVERSATION.VOICE_CALL.LIVE.ALERTS.INTERRUPTIONS_HINT',
      hintParams: { count: 4 },
    });
  });

  it('names a red call by its state', () => {
    const state = primaryCallState(
      liveCall(
        { attention: { takeoverRequest: { reason: 'looping', at: NOW } } },
        { needsAction: true }
      ),
      { now: NOW }
    );

    expect(attentionHeadline(state)).toMatchObject({
      level: 'red',
      labelKey: 'CALLS_PAGE.STATE.REQUESTED',
    });
  });

  it('has no level for a call the AI handles quietly', () => {
    const state = primaryCallState(liveCall(), { now: NOW });

    expect(attentionHeadline(state).level).toBeNull();
  });
});

describe('buildCallNotification', () => {
  it('says who, what, on which line, and links to the call', () => {
    const notification = buildCallNotification(parts());

    expect(notification).toMatchObject({
      tag: 'pathors-call-7',
      title: '陳先生：被打斷 4 次',
      body: '訂位專線 · +886912345678\n客人一直插話，可能不耐煩',
      level: 'amber',
      actions: [
        { action: 'take-over', title: '前往接手' },
        { action: 'dismiss', title: '略過' },
      ],
      data: {
        callId: 7,
        accountId: 3,
        url: '/app/accounts/3/calls/need?call=7',
      },
    });
  });

  it('names the caller by number when there is no name', () => {
    const notification = buildCallNotification(parts({ caller: '' }));

    expect(notification.title).toBe('+886912345678：被打斷 4 次');
    expect(notification.body).toBe('訂位專線\n客人一直插話，可能不耐煩');
  });

  it('changes its signature when what it says changes', () => {
    const before = buildCallNotification(parts()).signature;

    expect(buildCallNotification(parts()).signature).toBe(before);
    expect(
      buildCallNotification(parts({ heading: '被打斷 5 次' })).signature
    ).not.toBe(before);
    expect(buildCallNotification(parts({ level: 'red' })).signature).not.toBe(
      before
    );
  });
});

describe('callNotificationTag', () => {
  it('is one tag per call', () => {
    expect(callNotificationTag(12)).toBe('pathors-call-12');
  });
});

describe('notificationPermission', () => {
  it('is unsupported without the Notification API', () => {
    const { Notification } = globalThis;
    delete globalThis.Notification;
    try {
      expect(notificationPermission()).toBe('unsupported');
    } finally {
      globalThis.Notification = Notification;
    }
  });
});
