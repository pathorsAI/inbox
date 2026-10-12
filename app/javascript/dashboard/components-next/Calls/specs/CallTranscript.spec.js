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
