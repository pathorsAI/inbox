import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import MessageAPI from 'dashboard/api/inbox/message';
import { useAlert } from 'dashboard/composables';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import {
  CALL_IN_PROGRESS_NOTE_PREFIX,
  isCallNote,
} from 'dashboard/composables/useCallNotes';
import CallNotes from '../CallNotes.vue';

withFullI18n('zh_TW');

vi.mock('dashboard/api/inbox/message', () => ({
  default: { getPreviousMessages: vi.fn(), create: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const note = (id, overrides = {}) => ({
  id,
  private: true,
  content_type: 'text',
  content: `備註 ${id}`,
  created_at: 1_760_000_000 + id,
  conversation_id: 12,
  sender: { available_name: '小林' },
  ...overrides,
});

const PAGE = [
  { id: 1, private: false, content_type: 'voice_call', content: 'Voice call' },
  note(2, { content: `${CALL_IN_PROGRESS_NOTE_PREFIX}\n\nAI is on a call` }),
  note(3),
  { id: 4, private: true, content_type: 'pathors_handoff', content: '' },
  note(5, { content: '客人下午三點後方便回撥' }),
];

const mountNotes = (conversationId = 12) =>
  mount(CallNotes, { props: { conversationId } });

const find = (wrapper, id) => wrapper.find(`[data-test-id="${id}"]`);
const noteTexts = wrapper =>
  wrapper.findAll('[data-test-id="call-note"]').map(item => item.text());

describe('isCallNote', () => {
  it('keeps private text notes, not cards, bubbles or the call-start marker', () => {
    expect(PAGE.filter(isCallNote).map(message => message.id)).toEqual([3, 5]);
    expect(isCallNote(null)).toBe(false);
  });
});

describe('CallNotes', () => {
  beforeEach(() => {
    MessageAPI.getPreviousMessages.mockReset();
    MessageAPI.create.mockReset();
    useAlert.mockReset();
    MessageAPI.getPreviousMessages.mockResolvedValue({
      data: { payload: PAGE },
    });
  });

  it("lists the conversation's notes with who wrote them", async () => {
    const wrapper = mountNotes();
    await flushPromises();

    expect(MessageAPI.getPreviousMessages).toHaveBeenCalledWith({
      conversationId: 12,
      before: undefined,
    });
    const texts = noteTexts(wrapper);
    expect(texts).toHaveLength(2);
    expect(texts[0]).toContain('小林');
    expect(texts[1]).toContain('客人下午三點後方便回撥');
  });

  it('reads earlier pages until the first one', async () => {
    const fullPage = Array.from({ length: 20 }, (_, index) =>
      note(100 + index)
    );
    MessageAPI.getPreviousMessages
      .mockResolvedValueOnce({ data: { payload: fullPage } })
      .mockResolvedValueOnce({ data: { payload: [note(50)] } });

    const wrapper = mountNotes();
    await flushPromises();

    expect(MessageAPI.getPreviousMessages).toHaveBeenLastCalledWith({
      conversationId: 12,
      before: 100,
    });
    expect(noteTexts(wrapper)).toHaveLength(21);
    expect(noteTexts(wrapper)[0]).toContain('備註 50');
  });

  it('says so when there are none', async () => {
    MessageAPI.getPreviousMessages.mockResolvedValue({ data: { payload: [] } });
    const wrapper = mountNotes();
    await flushPromises();

    expect(find(wrapper, 'call-notes-empty').text()).toBe('還沒有備註');
  });

  it('adds a note as a private message of the conversation', async () => {
    MessageAPI.create.mockResolvedValue({
      data: note(9, { content: '已回撥' }),
    });
    const wrapper = mountNotes();
    await flushPromises();

    await find(wrapper, 'call-note-input')
      .find('textarea')
      .setValue(' 已回撥 ');
    await find(wrapper, 'call-note-save').trigger('click');
    await flushPromises();

    expect(MessageAPI.create).toHaveBeenCalledWith({
      conversationId: 12,
      message: '已回撥',
      private: true,
    });
    expect(noteTexts(wrapper).at(-1)).toContain('已回撥');
    expect(
      find(wrapper, 'call-note-input').find('textarea').element.value
    ).toBe('');
  });

  it('keeps the draft and says so when saving fails', async () => {
    MessageAPI.create.mockRejectedValue(new Error('500'));
    const wrapper = mountNotes();
    await flushPromises();

    await find(wrapper, 'call-note-input').find('textarea').setValue('已回撥');
    await find(wrapper, 'call-note-save').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('無法儲存備註');
    expect(
      find(wrapper, 'call-note-input').find('textarea').element.value
    ).toBe('已回撥');
  });

  it("shows a colleague's note on the same call as it arrives, once", async () => {
    const wrapper = mountNotes();
    await flushPromises();

    emitter.emit(
      BUS_EVENTS.PRIVATE_NOTE_CREATED,
      note(7, { content: '我來回' })
    );
    emitter.emit(
      BUS_EVENTS.PRIVATE_NOTE_CREATED,
      note(7, { content: '我來回' })
    );
    emitter.emit(
      BUS_EVENTS.PRIVATE_NOTE_CREATED,
      note(8, { conversation_id: 99 })
    );
    await flushPromises();

    expect(noteTexts(wrapper)).toHaveLength(3);
    expect(noteTexts(wrapper).at(-1)).toContain('我來回');
    wrapper.unmount();
  });

  it('loads the notes of another call when the sheet switches to it', async () => {
    const wrapper = mountNotes();
    await flushPromises();
    MessageAPI.getPreviousMessages.mockResolvedValue({ data: { payload: [] } });

    await wrapper.setProps({ conversationId: 13 });
    await flushPromises();

    expect(MessageAPI.getPreviousMessages).toHaveBeenLastCalledWith({
      conversationId: 13,
      before: undefined,
    });
    expect(noteTexts(wrapper)).toEqual([]);
  });

  it('caps a note at 2000 characters', async () => {
    const wrapper = mountNotes();
    await flushPromises();

    expect(
      find(wrapper, 'call-note-input').find('textarea').attributes('maxlength')
    ).toBe('2000');
  });

  it('stops loading when it switches to a call without a conversation mid-load', async () => {
    MessageAPI.getPreviousMessages.mockReturnValue(new Promise(() => {}));
    const wrapper = mountNotes();
    await flushPromises();
    expect(wrapper.text()).toContain('載入備註中');

    await wrapper.setProps({ conversationId: null });
    await flushPromises();

    expect(wrapper.text()).not.toContain('載入備註中');
  });

  it("keeps a colleague's note that arrives while the notes are loading", async () => {
    let resolvePage;
    MessageAPI.getPreviousMessages.mockReturnValue(
      new Promise(resolve => {
        resolvePage = resolve;
      })
    );
    const wrapper = mountNotes();
    await flushPromises();

    emitter.emit(
      BUS_EVENTS.PRIVATE_NOTE_CREATED,
      note(7, { content: '我來回' })
    );
    resolvePage({ data: { payload: PAGE } });
    await flushPromises();

    expect(noteTexts(wrapper)).toHaveLength(3);
    expect(noteTexts(wrapper).at(-1)).toContain('我來回');
    wrapper.unmount();
  });
});
