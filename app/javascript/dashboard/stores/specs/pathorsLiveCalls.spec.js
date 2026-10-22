import { setActivePinia, createPinia } from 'pinia';
import PathorsCallsAPI from 'dashboard/api/pathorsCalls';
import {
  usePathorsLiveCallsStore,
  resetPathorsLiveCallsTracking,
} from '../pathorsLiveCalls';

vi.mock('dashboard/api/pathorsCalls', () => ({
  default: { active: vi.fn(), dismiss: vi.fn() },
}));

const buildMessage = ({ call = {}, ...overrides } = {}) => ({
  id: 501,
  content_type: 'voice_call',
  message_type: 0,
  conversation_id: 12,
  inbox_id: 3,
  sender: { name: 'Wang', phone_number: '+886912345678' },
  call: {
    id: 77,
    provider: 'pathors',
    status: 'in-progress',
    started_at: '2026-10-04T10:00:00Z',
    accepted_by_agent_id: null,
    ...call,
  },
  ...overrides,
});

const liveUpdate = (live, id = 77) => ({
  id,
  conversation_id: 12,
  account_id: 1,
  live,
});

describe('pathorsLiveCalls store', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    resetPathorsLiveCallsTracking();
    vi.clearAllMocks();
  });

  it('loads the active calls camelized, keeping their live state apart', async () => {
    PathorsCallsAPI.active.mockResolvedValue({
      payload: [
        {
          id: 77,
          conversation_id: 12,
          inbox_name: 'Front desk',
          live: {
            seq: 4,
            transfer_failed: true,
            transcript: [{ kind: 'message', role: 'user', content: 'hi' }],
          },
        },
      ],
    });
    const store = usePathorsLiveCallsStore();

    await store.fetchActive();

    expect(store.records).toEqual([
      { id: 77, conversationId: 12, inboxName: 'Front desk' },
    ]);
    expect(store.liveById[77]).toEqual({
      seq: 4,
      transferFailed: true,
      transcript: [{ kind: 'message', role: 'user', content: 'hi' }],
    });
    expect(store.hasLoaded).toBe(true);
  });

  it('keeps a call that rang while the fetch was in flight', async () => {
    let resolveFetch;
    PathorsCallsAPI.active.mockReturnValue(
      new Promise(resolve => {
        resolveFetch = resolve;
      })
    );
    const store = usePathorsLiveCallsStore();

    const fetching = store.fetchActive();
    store.syncFromMessage(buildMessage({ call: { id: 88 }, id: 502 }));
    resolveFetch({ payload: [{ id: 77, conversation_id: 12 }] });
    await fetching;

    expect(store.records.map(record => record.id).sort()).toEqual([77, 88]);
  });

  it('drops live state for calls the fetch no longer reports', async () => {
    const store = usePathorsLiveCallsStore();
    store.applyLive(77, { seq: 3, turns: 5 });
    store.records = [{ id: 77, conversationId: 12 }];
    PathorsCallsAPI.active.mockResolvedValue({ payload: [] });

    await store.fetchActive();

    expect(store.records).toEqual([]);
    expect(store.liveById).toEqual({});
  });

  it('tells whether a conversation has a call still on the line', () => {
    const store = usePathorsLiveCallsStore();
    store.syncFromMessage(buildMessage());

    expect(store.hasLiveCallInConversation(12)).toBe(true);
    expect(store.hasLiveCallInConversation(13)).toBe(false);
    expect(store.hasLiveCallInConversation(undefined)).toBe(false);

    store.syncFromMessage(buildMessage({ call: { status: 'completed' } }));
    expect(store.hasLiveCallInConversation(12)).toBe(false);
  });

  it('loads once however many bubbles ask, and not again once loaded', async () => {
    PathorsCallsAPI.active.mockResolvedValue({ payload: [] });
    const store = usePathorsLiveCallsStore();

    await Promise.all([store.ensureLoaded(), store.ensureLoaded()]);
    await store.ensureLoaded();

    expect(PathorsCallsAPI.active).toHaveBeenCalledTimes(1);
  });

  it('survives a failed load so the next turn can still fill the bubble', async () => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    PathorsCallsAPI.active.mockRejectedValue(new Error('offline'));
    const store = usePathorsLiveCallsStore();

    await expect(store.ensureLoaded()).resolves.toBeUndefined();
    expect(store.hasLoaded).toBe(false);
  });

  it('adds a live pathors call from its message', () => {
    const store = usePathorsLiveCallsStore();

    store.syncFromMessage(buildMessage());

    expect(store.records).toHaveLength(1);
    expect(store.records[0]).toMatchObject({
      id: 77,
      status: 'in-progress',
      messageId: 501,
      conversationId: 12,
      inboxId: 3,
      contactName: 'Wang',
      contactPhoneNumber: '+886912345678',
    });
  });

  it('updates in place and keeps what the fetch knew', async () => {
    PathorsCallsAPI.active.mockResolvedValue({
      payload: [
        {
          id: 77,
          inbox_name: 'Front desk',
          contact_name: 'Wang',
          live: { seq: 1 },
        },
      ],
    });
    const store = usePathorsLiveCallsStore();
    await store.fetchActive();

    store.syncFromMessage(
      buildMessage({
        message_type: 1,
        sender: null,
        call: { accepted_by_agent_id: 9 },
      })
    );

    expect(store.records).toHaveLength(1);
    expect(store.records[0]).toMatchObject({
      acceptedByAgentId: 9,
      inboxName: 'Front desk',
      contactName: 'Wang',
    });
    expect(store.liveById[77]).toEqual({ seq: 1 });
  });

  it('takes live updates from the broadcast, newest seq wins', () => {
    const store = usePathorsLiveCallsStore();

    store.handleLiveUpdated(liveUpdate({ seq: 5, turns: 9 }));
    store.handleLiveUpdated(liveUpdate({ seq: 4, turns: 8 }));
    expect(store.liveById[77]).toEqual({ seq: 5, turns: 9 });

    store.handleLiveUpdated(
      liveUpdate({ seq: 6, turns: 10, transfer_failed: true })
    );
    expect(store.liveById[77]).toEqual({
      seq: 6,
      turns: 10,
      transferFailed: true,
    });
  });

  it('keeps a newer broadcast over an older fetch result', async () => {
    const store = usePathorsLiveCallsStore();
    store.handleLiveUpdated(liveUpdate({ seq: 8, turns: 12 }));
    PathorsCallsAPI.active.mockResolvedValue({
      payload: [{ id: 77, live: { seq: 7, turns: 11 } }],
    });

    await store.fetchActive();

    expect(store.liveById[77]).toEqual({ seq: 8, turns: 12 });
  });

  it('removes the call and its live state when it ends, and nothing revives it', async () => {
    const store = usePathorsLiveCallsStore();
    store.syncFromMessage(buildMessage());
    store.handleLiveUpdated(liveUpdate({ seq: 1, turns: 1 }));

    store.syncFromMessage(buildMessage({ call: { status: 'completed' } }));
    expect(store.records).toEqual([]);
    expect(store.liveById).toEqual({});

    PathorsCallsAPI.active.mockResolvedValue({
      payload: [{ id: 77, live: { seq: 2 } }],
    });
    await store.fetchActive();
    store.syncFromMessage(buildMessage());
    store.handleLiveUpdated(liveUpdate({ seq: 3 }));

    expect(store.records).toEqual([]);
    expect(store.liveById).toEqual({});
  });

  it('keeps the variables of a handoff card on the live call in its conversation', () => {
    const store = usePathorsLiveCallsStore();
    store.syncFromMessage(buildMessage());

    store.syncHandoffCard({
      id: 900,
      content_type: 'pathors_handoff',
      conversation_id: 12,
      content_attributes: {
        data: { variables: { customer_name: '林先生', email: null } },
      },
    });

    expect(store.records[0].variables).toEqual({
      customer_name: '林先生',
      email: null,
    });

    // A later status broadcast does not carry them, and does not drop them.
    store.syncFromMessage(buildMessage({ call: { accepted_by_agent_id: 9 } }));
    expect(store.records[0].variables).toEqual({
      customer_name: '林先生',
      email: null,
    });
  });

  it('keeps the AI variables verbatim from the active seed', async () => {
    PathorsCallsAPI.active.mockResolvedValue({
      payload: [
        {
          id: 77,
          conversation_id: 12,
          variables: { customer_name: '林先生' },
        },
      ],
    });
    const store = usePathorsLiveCallsStore();

    await store.fetchActive();

    expect(store.records[0].variables).toEqual({ customer_name: '林先生' });
  });

  it('keeps a handoff card that arrives while a fetch is in flight', async () => {
    const store = usePathorsLiveCallsStore();
    store.syncFromMessage(buildMessage());
    await Promise.resolve();
    let resolveFetch;
    PathorsCallsAPI.active.mockReturnValue(
      new Promise(resolve => {
        resolveFetch = resolve;
      })
    );

    const fetching = store.fetchActive();
    store.syncHandoffCard({
      content_type: 'pathors_handoff',
      conversation_id: 12,
      content_attributes: { data: { variables: { customer_name: '林先生' } } },
    });
    // The snapshot was read before the card existed.
    resolveFetch({
      payload: [
        { id: 77, conversation_id: 12, status: 'in-progress', variables: null },
      ],
    });
    await fetching;

    expect(store.records[0].variables).toEqual({ customer_name: '林先生' });
  });

  it('ignores other messages, and handoff cards from conversations without a live call', () => {
    const store = usePathorsLiveCallsStore();
    store.syncFromMessage(buildMessage());

    store.syncHandoffCard({ content_type: 'text', conversation_id: 12 });
    store.syncHandoffCard({
      content_type: 'pathors_handoff',
      conversation_id: 13,
      content_attributes: { data: { variables: { a: 1 } } },
    });

    expect(store.records[0].variables).toBeUndefined();
  });

  it('ignores other providers and other message types', () => {
    const store = usePathorsLiveCallsStore();

    store.syncFromMessage(buildMessage({ call: { provider: 'twilio' } }));
    store.syncFromMessage(buildMessage({ content_type: 'text' }));

    expect(store.records).toEqual([]);
  });

  describe('handling state', () => {
    const seed = async payload => {
      PathorsCallsAPI.active.mockResolvedValue({ payload });
      const store = usePathorsLiveCallsStore();
      await store.fetchActive();
      return store;
    };

    const activeCall = (id, overrides = {}) => ({
      id,
      provider: 'pathors',
      status: 'in-progress',
      conversation_id: 12,
      started_at: '2026-10-11T10:00:00Z',
      needs_action: false,
      dismissed: false,
      accepted_at: null,
      ...overrides,
    });

    it('keeps needsAction, followUp, dismissed and acceptedAt from the active seed', async () => {
      const store = await seed([
        activeCall(77, {
          needs_action: true,
          follow_up: false,
          takeover_requested: true,
          accepted_at: 1_760_000_000_000,
          live: { seq: 1 },
        }),
      ]);

      expect(store.records[0]).toMatchObject({
        needsAction: true,
        followUp: false,
        dismissed: false,
        takeoverRequested: true,
        acceptedAt: 1_760_000_000_000,
      });
    });

    it('applies needs_action and the agent on the call from live_updated', async () => {
      const store = await seed([activeCall(77, { live: { seq: 1 } })]);

      store.handleLiveUpdated({
        ...liveUpdate({ seq: 2 }),
        needs_action: true,
        accepted_by_agent_id: null,
      });
      expect(store.records[0].needsAction).toBe(true);

      store.handleLiveUpdated({
        ...liveUpdate({ seq: 2 }),
        needs_action: false,
        accepted_by_agent_id: 9,
      });
      expect(store.records[0]).toMatchObject({
        needsAction: false,
        acceptedByAgentId: 9,
      });
    });

    it('ignores the handling state of an older turn', async () => {
      const store = await seed([
        activeCall(77, { needs_action: true, live: { seq: 5 } }),
      ]);

      store.handleLiveUpdated({
        ...liveUpdate({ seq: 4 }),
        needs_action: false,
      });

      expect(store.records[0].needsAction).toBe(true);
      expect(store.liveById[77].seq).toBe(5);
    });

    // A minute into calls that started at 10:00: nothing is amber by the clock.
    const NOW = Date.parse('2026-10-11T10:01:00Z');
    const ids = store => store.attentionCallsAt(NOW).map(call => call.id);

    it('lists red calls, unmuted, most recent request first', async () => {
      const store = await seed([
        activeCall(1, {
          needs_action: true,
          live: {
            seq: 1,
            attention: { takeover_request: { reason: 'looping', at: 1000 } },
          },
        }),
        activeCall(2, {
          needs_action: true,
          live: {
            seq: 1,
            attention: { transfer: { phase: 'failed', at: 5000 } },
          },
        }),
        activeCall(3, { needs_action: true, dismissed: true }),
        activeCall(4, { needs_action: false }),
      ]);

      const calls = store.attentionCallsAt(NOW);
      expect(calls.map(call => call.id)).toEqual([2, 1]);
      expect(calls[0].live.attention.transfer.phase).toBe('failed');
      expect(calls[0].callState.key).toBe('transfer_failed');
    });

    it('lists amber calls after the red ones', async () => {
      const store = await seed([
        activeCall(1, { live: { seq: 1, interruptions: 4 } }),
        activeCall(2, { needs_action: true }),
        activeCall(3, { live: { seq: 1, interruptions: 3 } }),
      ]);

      expect(ids(store)).toEqual([2, 1]);
      expect(store.attentionCallsAt(NOW)[1].callState.key).toBe('warn');
    });

    it('turns a long call amber by the clock alone', async () => {
      const store = await seed([activeCall(1)]);

      expect(ids(store)).toEqual([]);
      expect(
        store
          .attentionCallsAt(Date.parse('2026-10-11T10:06:00Z'))
          .map(call => call.id)
      ).toEqual([1]);
    });

    it('dismisses optimistically and keeps it once the server agrees', async () => {
      const store = await seed([activeCall(77, { needs_action: true })]);
      let resolveRequest;
      PathorsCallsAPI.dismiss.mockReturnValue(
        new Promise(resolve => {
          resolveRequest = resolve;
        })
      );

      const pending = store.dismissAttention(77, 'red');
      expect(ids(store)).toEqual([]);
      resolveRequest({ dismissed: true });
      await pending;

      expect(PathorsCallsAPI.dismiss).toHaveBeenCalledWith(77);
      expect(store.records[0].dismissed).toBe(true);
    });

    it('brings the alert back and rethrows when dismissing fails', async () => {
      const store = await seed([activeCall(77, { needs_action: true })]);
      PathorsCallsAPI.dismiss.mockRejectedValue(new Error('nope'));

      await expect(store.dismissAttention(77, 'red')).rejects.toThrow('nope');

      expect(store.records[0].dismissed).toBe(false);
      expect(ids(store)).toEqual([77]);
    });

    it('mutes an amber call here only, and not once the AI asks for help', async () => {
      const store = await seed([
        activeCall(77, { live: { seq: 1, interruptions: 4 } }),
      ]);

      await store.dismissAttention(77, 'amber');
      expect(PathorsCallsAPI.dismiss).not.toHaveBeenCalled();
      expect(ids(store)).toEqual([]);

      store.handleLiveUpdated({
        ...liveUpdate({ seq: 2, interruptions: 4 }),
        needs_action: true,
      });
      expect(ids(store)).toEqual([77]);
    });

    it('keeps an amber mute across a reload of the active calls', async () => {
      const store = await seed([
        activeCall(77, { live: { seq: 1, interruptions: 4 } }),
      ]);
      await store.dismissAttention(77, 'amber');

      await store.fetchActive();

      expect(store.records[0].warningMuted).toBe(true);
      expect(ids(store)).toEqual([]);
    });

    describe('handlingSignatureAt', () => {
      const STARTED = Date.parse('2026-10-11T10:00:00Z');
      const now = STARTED + 60_000;

      it('changes only when a call moves, not per turn', async () => {
        const store = await seed([activeCall(77, { live: { seq: 1 } })]);
        const before = store.handlingSignatureAt(now);

        store.handleLiveUpdated({
          ...liveUpdate({ seq: 2, turns: 3 }),
          needs_action: false,
        });
        expect(store.handlingSignatureAt(now)).toBe(before);

        store.handleLiveUpdated({
          ...liveUpdate({ seq: 3, turns: 4 }),
          needs_action: true,
        });
        expect(store.handlingSignatureAt(now)).not.toBe(before);
      });

      it('changes when a call turns amber, from its counters or the clock alone', async () => {
        const store = await seed([activeCall(77, { live: { seq: 1 } })]);
        const before = store.handlingSignatureAt(now);

        expect(store.handlingSignatureAt(now + 60_000)).toBe(before);
        expect(store.handlingSignatureAt(STARTED + 301_000)).not.toBe(before);

        store.handleLiveUpdated(liveUpdate({ seq: 2, turns: 21 }));
        expect(store.handlingSignatureAt(now)).not.toBe(before);
      });

      it('changes when a human takes an amber call', async () => {
        const store = await seed([
          activeCall(77, { live: { seq: 1, interruptions: 4 } }),
        ]);
        const before = store.handlingSignatureAt(now);

        store.handleLiveUpdated({
          ...liveUpdate({ seq: 2, interruptions: 4 }),
          accepted_by_agent_id: 5,
        });
        expect(store.handlingSignatureAt(now)).not.toBe(before);
      });
    });

    it('remembers which call the sheet has open', () => {
      const store = usePathorsLiveCallsStore();

      store.setOpenCallId(77);
      expect(store.openCallId).toBe(77);
      store.setOpenCallId(null);
      expect(store.openCallId).toBeNull();
    });
  });
});
