import { setActivePinia, createPinia } from 'pinia';
import PathorsCallsAPI from 'dashboard/api/pathorsCalls';
import {
  usePathorsLiveCallsStore,
  resetPathorsLiveCallsTracking,
} from '../pathorsLiveCalls';

vi.mock('dashboard/api/pathorsCalls', () => ({
  default: { active: vi.fn() },
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

  it('ignores other providers and other message types', () => {
    const store = usePathorsLiveCallsStore();

    store.syncFromMessage(buildMessage({ call: { provider: 'twilio' } }));
    store.syncFromMessage(buildMessage({ content_type: 'text' }));

    expect(store.records).toEqual([]);
  });
});
