import ConversationAPI from 'dashboard/api/inbox/conversation';
import {
  callRedirectFor,
  conversationIdOf,
} from 'dashboard/helper/callConversationRoute';

vi.mock('dashboard/api/inbox/conversation', () => ({
  default: { show: vi.fn() },
}));

const VOICE = { meta: { channel: 'Channel::Voice' } };
const CHAT = { meta: { channel: 'Channel::WebWidget' } };
const CALLS_LOCATION = {
  name: 'calls_all',
  params: { accountId: '1' },
  query: { conversation: '42' },
};

const conversationRoute = {
  name: 'inbox_conversation',
  params: { accountId: '1', conversation_id: '42' },
};

describe('conversationIdOf', () => {
  it('reads the conversation of every conversation view', () => {
    expect(conversationIdOf(conversationRoute)).toBe('42');
    expect(
      conversationIdOf({
        name: 'conversation_through_mentions',
        params: { conversation_id: '7' },
      })
    ).toBe('7');
  });

  it('reads the conversation of a notification', () => {
    expect(
      conversationIdOf({
        name: 'inbox_view_conversation',
        params: { type: 'conversation', id: '9' },
      })
    ).toBe('9');
  });

  it('is null for any other route', () => {
    expect(conversationIdOf({ name: 'calls_all', params: {} })).toBeNull();
    expect(
      conversationIdOf({
        name: 'inbox_view_conversation',
        params: { type: 'other', id: '9' },
      })
    ).toBeNull();
  });
});

describe('callRedirectFor', () => {
  beforeEach(() => {
    ConversationAPI.show.mockReset();
  });

  it('sends a loaded call conversation to the calls page', async () => {
    const getConversationById = vi.fn(() => VOICE);

    await expect(
      callRedirectFor(conversationRoute, getConversationById)
    ).resolves.toEqual(CALLS_LOCATION);
    expect(getConversationById).toHaveBeenCalledWith('42');
    expect(ConversationAPI.show).not.toHaveBeenCalled();
  });

  it('fetches a conversation the store does not have', async () => {
    ConversationAPI.show.mockResolvedValue({ data: VOICE });

    await expect(
      callRedirectFor(conversationRoute, () => undefined)
    ).resolves.toEqual(CALLS_LOCATION);
    expect(ConversationAPI.show).toHaveBeenCalledWith('42');
  });

  it('lets other conversations through', async () => {
    await expect(
      callRedirectFor(conversationRoute, () => CHAT)
    ).resolves.toBeNull();
  });

  it('lets the conversation view report a conversation it cannot load', async () => {
    ConversationAPI.show.mockRejectedValue(new Error('404'));

    await expect(
      callRedirectFor(conversationRoute, () => undefined)
    ).resolves.toBeNull();
  });

  it('does nothing on routes without a conversation', async () => {
    const getConversationById = vi.fn();

    await expect(
      callRedirectFor({ name: 'home', params: {} }, getConversationById)
    ).resolves.toBeNull();
    expect(getConversationById).not.toHaveBeenCalled();
  });
});
