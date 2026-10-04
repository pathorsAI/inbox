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
    live: {
      seq: 2,
      turns: 4,
      interruptions: 1,
      transfer_failed: false,
      transcript: [{ kind: 'message', role: 'user', content: 'hi' }],
    },
    ...call,
  },
  ...overrides,
});

describe('pathorsLiveCalls store', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    resetPathorsLiveCallsTracking();
    vi.clearAllMocks();
  });

  it('loads the active calls camelized', async () => {
    PathorsCallsAPI.active.mockResolvedValue({
      payload: [
        { id: 77, conversation_id: 12, inbox_name: 'Front desk', live: null },
      ],
    });
    const store = usePathorsLiveCallsStore();

    await store.fetchActive();

    expect(store.records).toEqual([
      { id: 77, conversationId: 12, inboxName: 'Front desk', live: null },
    ]);
  });

  it('adds a live pathors call from its message with only the live counters', () => {
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
      live: { seq: 2, turns: 4, interruptions: 1, transferFailed: false },
    });
  });

  it('updates in place and keeps what the fetch knew', async () => {
    PathorsCallsAPI.active.mockResolvedValue({
      payload: [{ id: 77, inbox_name: 'Front desk', contact_name: 'Wang' }],
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
  });

  it('ignores a turn older than the one it already has', () => {
    const store = usePathorsLiveCallsStore();
    store.syncFromMessage(
      buildMessage({ call: { live: { seq: 5, turns: 9 } } })
    );

    store.syncFromMessage(
      buildMessage({ call: { live: { seq: 4, turns: 8 } } })
    );

    expect(store.records[0].live.turns).toBe(9);
  });

  it('removes the call when it ends and does not let a late fetch revive it', async () => {
    const store = usePathorsLiveCallsStore();
    store.syncFromMessage(buildMessage());

    store.syncFromMessage(buildMessage({ call: { status: 'completed' } }));
    expect(store.records).toEqual([]);

    PathorsCallsAPI.active.mockResolvedValue({ payload: [{ id: 77 }] });
    await store.fetchActive();
    store.syncFromMessage(buildMessage());

    expect(store.records).toEqual([]);
  });

  it('ignores other providers and other message types', () => {
    const store = usePathorsLiveCallsStore();

    store.syncFromMessage(buildMessage({ call: { provider: 'twilio' } }));
    store.syncFromMessage(buildMessage({ content_type: 'text' }));

    expect(store.records).toEqual([]);
  });
});
