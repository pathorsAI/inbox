import { onBeforeUnmount, ref, watch } from 'vue';
import MessageAPI from 'dashboard/api/inbox/message';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

// The voice bridge's English start-of-call marker (pathorsAI/pathors
// voice-bridge.ts). The call sheet's status bar already says it.
export const CALL_IN_PROGRESS_NOTE_PREFIX = '📞 **Call in progress**';
// MessageFinder's page; a shorter page is the first one.
const MESSAGES_PAGE_SIZE = 20;

/**
 * A note on a call: a private text message of its conversation. Hand-off cards
 * and the call bubble have their own content types and their own places.
 * @param {Object} message - A raw (snake_case) message
 * @returns {boolean}
 */
export const isCallNote = message =>
  !!message?.private &&
  message.content_type === 'text' &&
  !!message.content &&
  !message.content.startsWith(CALL_IN_PROGRESS_NOTE_PREFIX);

const fetchMessages = async (conversationId, before) => {
  const { data } = await MessageAPI.getPreviousMessages({
    conversationId,
    before,
  });
  const page = data.payload;
  if (page.length < MESSAGES_PAGE_SIZE) return page;
  return [...(await fetchMessages(conversationId, page[0].id)), ...page];
};

const byCreatedAt = (a, b) => a.created_at - b.created_at;

/**
 * The private notes of a call's conversation, and adding one. Notes stay on
 * the conversation, so whoever picks the conversation up (or calls back)
 * sees them wherever they look.
 * @param {import('vue').Ref<number|null>} conversationId - Its display id
 */
export function useCallNotes(conversationId) {
  const notes = ref([]);
  const isLoading = ref(false);
  const hasLoadError = ref(false);
  const isSaving = ref(false);

  const isCurrent = id => Number(conversationId.value) === Number(id);

  const addNote = message => {
    if (!isCallNote(message)) return;
    if (notes.value.some(note => note.id === message.id)) return;
    notes.value = [...notes.value, message].sort(byCreatedAt);
  };

  const load = async id => {
    notes.value = [];
    hasLoadError.value = false;
    if (!id) return;
    isLoading.value = true;
    try {
      const messages = await fetchMessages(id);
      if (isCurrent(id)) notes.value = messages.filter(isCallNote);
    } catch {
      if (isCurrent(id)) hasLoadError.value = true;
    } finally {
      if (isCurrent(id)) isLoading.value = false;
    }
  };

  /**
   * @param {string} content
   * @returns {Promise<boolean>} Whether the note was saved
   */
  const create = async content => {
    const id = conversationId.value;
    isSaving.value = true;
    try {
      const { data } = await MessageAPI.create({
        conversationId: id,
        message: content,
        private: true,
      });
      if (isCurrent(id)) addNote(data);
      return true;
    } catch {
      return false;
    } finally {
      isSaving.value = false;
    }
  };

  // A colleague's note on the same call shows up without a reload.
  const onNoteCreated = message => {
    if (isCurrent(message.conversation_id)) addNote(message);
  };
  emitter.on(BUS_EVENTS.PRIVATE_NOTE_CREATED, onNoteCreated);
  onBeforeUnmount(() =>
    emitter.off(BUS_EVENTS.PRIVATE_NOTE_CREATED, onNoteCreated)
  );

  watch(conversationId, load, { immediate: true });

  return { notes, isLoading, hasLoadError, isSaving, create };
}
