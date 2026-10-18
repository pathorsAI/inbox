import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import CallTranscript from '../CallTranscript.vue';

withFullI18n('zh_TW');

const lines = count =>
  Array.from({ length: count }, (_, index) => ({
    kind: 'message',
    role: index % 2 ? 'user' : 'assistant',
    content: `第 ${index + 1} 句`,
  }));

// jsdom has no layout: give the list a fixed box so scroll positions mean
// something.
const setBox = (el, { scrollHeight, clientHeight = 200 }) => {
  Object.defineProperty(el, 'scrollHeight', {
    configurable: true,
    value: scrollHeight,
  });
  Object.defineProperty(el, 'clientHeight', {
    configurable: true,
    value: clientHeight,
  });
};

// Settles the scroll the first render queues before the spec moves the list.
const mountTranscript = async props => {
  const wrapper = mount(CallTranscript, {
    props: { entries: lines(10), seq: 1, isLive: true, ...props },
    attachTo: document.body,
  });
  await flushPromises();
  return wrapper;
};

const list = wrapper => wrapper.find('[data-test-id="call-transcript"]');
const jump = wrapper => wrapper.find('[data-test-id="call-transcript-jump"]');

describe('CallTranscript', () => {
  describe('as a chat', () => {
    const say = (role, content, extra = {}) => ({
      kind: 'message',
      role,
      content,
      ...extra,
    });
    const divider = {
      kind: 'system',
      code: 'transfer_started',
      text: '轉接中',
    };
    const messages = wrapper =>
      wrapper.findAll(
        '[data-test-id="call-transcript-ai"], [data-test-id="call-transcript-caller"]'
      );
    const roleOf = row => {
      const role = row.find('[data-test-id="call-transcript-role"]');
      return role.exists() ? role.text() : null;
    };

    it('puts the caller on the left and the AI on the right', async () => {
      const wrapper = await mountTranscript({
        entries: [say('user', '你好'), say('assistant', '您好')],
      });
      const caller = wrapper.find('[data-test-id="call-transcript-caller"]');
      const ai = wrapper.find('[data-test-id="call-transcript-ai"]');

      expect(caller.classes()).toContain('items-start');
      expect(caller.find('p').classes()).toContain('bg-n-slate-3');
      expect(ai.classes()).toContain('items-end');
      expect(ai.find('p').classes()).toContain('bg-n-blue-3');
      wrapper.unmount();
    });

    it('names the speaker only when it changes, and again after a divider', async () => {
      const wrapper = await mountTranscript({
        entries: [
          say('assistant', '您好'),
          say('assistant', '請問有什麼需要'),
          say('user', '我想問報價'),
          say('user', '還有合約'),
          divider,
          say('user', '喂？'),
          say('assistant', '幫您轉接'),
        ],
      });

      expect(messages(wrapper).map(roleOf)).toEqual([
        'AI',
        null,
        '客人',
        null,
        '客人',
        'AI',
      ]);
      wrapper.unmount();
    });

    it('frames a cut-off line and tags it underneath', async () => {
      const wrapper = await mountTranscript({
        entries: [say('assistant', '我們的方案有', { interrupted: true })],
      });
      const row = wrapper.find('[data-test-id="call-transcript-ai"]');
      const bubble = row.find('p');
      const tag = row.find('[data-test-id="call-transcript-interrupted"]');

      expect(bubble.classes()).toContain('outline-dashed');
      expect(bubble.classes()).toContain('outline-n-amber-9');
      expect(tag.text()).toBe('被打斷');
      // Under the bubble, on the same side.
      expect(row.element.lastElementChild).toBe(tag.element);
      expect(row.classes()).toContain('items-end');
      wrapper.unmount();
    });

    it('leaves a line that was not cut off unframed and untagged', async () => {
      const wrapper = await mountTranscript({
        entries: [say('assistant', '您好')],
      });
      const row = wrapper.find('[data-test-id="call-transcript-ai"]');

      expect(row.find('p').classes()).not.toContain('outline-dashed');
      expect(
        row.find('[data-test-id="call-transcript-interrupted"]').exists()
      ).toBe(false);
      wrapper.unmount();
    });
  });

  it('draws a transfer a human cancelled as a hand-off, not a failure', async () => {
    const system = (code, text) => ({ kind: 'system', code, text, at: 1 });
    const wrapper = await mountTranscript({
      entries: [
        system('transfer_failed', '轉接失敗：無人接聽'),
        system('transfer_cancelled', '轉接已取消：真人接手'),
      ],
    });
    const row = code => wrapper.find(`[data-code="${code}"]`);

    expect(row('transfer_failed').classes()).toContain('text-n-ruby-11');
    expect(row('transfer_cancelled').classes()).toContain('text-n-blue-11');
  });

  it('follows new lines to the bottom while the reader stays there', async () => {
    const wrapper = await mountTranscript();
    const el = list(wrapper).element;
    setBox(el, { scrollHeight: 1000 });

    await wrapper.setProps({ entries: lines(11), seq: 2 });
    await flushPromises();

    expect(el.scrollTop).toBe(1000);
    expect(jump(wrapper).exists()).toBe(false);
    wrapper.unmount();
  });

  it('stops following once the reader scrolls up, and offers a way back', async () => {
    const wrapper = await mountTranscript();
    const el = list(wrapper).element;
    setBox(el, { scrollHeight: 1000 });
    el.scrollTop = 500;
    await list(wrapper).trigger('scroll');

    await wrapper.setProps({ entries: lines(11), seq: 2 });
    await flushPromises();
    expect(el.scrollTop).toBe(500);
    expect(jump(wrapper).text()).toContain('回到最新');

    await jump(wrapper).trigger('click');
    expect(el.scrollTop).toBe(1000);
    expect(jump(wrapper).exists()).toBe(false);

    await wrapper.setProps({ entries: lines(12), seq: 3 });
    setBox(el, { scrollHeight: 1100 });
    await flushPromises();
    expect(el.scrollTop).toBe(1100);
    wrapper.unmount();
  });

  it('still counts a reader just short of the bottom as following', async () => {
    const wrapper = await mountTranscript();
    const el = list(wrapper).element;
    setBox(el, { scrollHeight: 1000 });
    el.scrollTop = 770;
    await list(wrapper).trigger('scroll');

    expect(jump(wrapper).exists()).toBe(false);
    wrapper.unmount();
  });

  it('offers no way back on an ended call', async () => {
    const wrapper = await mountTranscript({ isLive: false });
    const el = list(wrapper).element;
    setBox(el, { scrollHeight: 1000 });
    el.scrollTop = 0;
    await list(wrapper).trigger('scroll');

    expect(jump(wrapper).exists()).toBe(false);
    wrapper.unmount();
  });

  it('says so when there is no transcript yet', async () => {
    const wrapper = await mountTranscript({ entries: [] });

    expect(list(wrapper).exists()).toBe(false);
    expect(wrapper.text()).toContain('還沒有逐字稿');
    wrapper.unmount();
  });
});
