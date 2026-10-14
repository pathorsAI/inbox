import ConversationAPI from 'dashboard/api/inbox/conversation';
import { isCallConversation } from 'dashboard/store/modules/conversations/helpers';

// A call's conversation is never shown as a conversation: every way into it
// (a contact's history, search results, a notification, a pasted link) lands
// on the calls page, which opens the call's sheet.
export const CALLS_ROUTE_NAME = 'calls_all';

// Every conversation view names its conversation `conversation_id`; the
// notifications inbox routes it as `:type/:id`.
export const conversationIdOf = ({ name, params = {} }) => {
  if (params.conversation_id) return params.conversation_id;
  if (name === 'inbox_view_conversation' && params.type === 'conversation') {
    return params.id;
  }
  return null;
};

const loadConversation = async (conversationId, getConversationById) => {
  const loaded = getConversationById(conversationId);
  if (loaded) return loaded;
  try {
    const { data } = await ConversationAPI.show(conversationId);
    return data;
  } catch {
    // Not found or not allowed: the conversation view reports that itself.
    return null;
  }
};

/**
 * Where to send a navigation to a call's conversation, or null to let it
 * through.
 * @param {Object} to - The route being entered
 * @param {Function} getConversationById - The conversations store getter
 * @returns {Promise<Object|null>} The calls page location, or null
 */
export const callRedirectFor = async (to, getConversationById) => {
  const conversationId = conversationIdOf(to);
  if (!conversationId) return null;

  const conversation = await loadConversation(
    conversationId,
    getConversationById
  );
  if (!isCallConversation(conversation)) return null;

  return {
    name: CALLS_ROUTE_NAME,
    params: { accountId: to.params.accountId },
    query: { conversation: String(conversationId) },
  };
};
