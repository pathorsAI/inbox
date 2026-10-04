import { nextTick } from 'vue';
import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import PathorsLiveMonitor from '../PathorsLiveMonitor.vue';

withFullI18n();

// Relative to the faked clock, which the tick test advances.
const secondsAgo = seconds =>
  new Date(Date.now() - seconds * 1000).toISOString();

const transcript = [
  { kind: 'message', role: 'user', content: 'I want a private room', at: 1 },
  {
    kind: 'message',
    role: 'assistant',
    content: 'For Friday at seven we have',
    interrupted: true,
    at: 2,
  },
  {
    kind: 'system',
    code: 'transfer_failed',
    text: 'Transfer failed: line busy',
    at: 3,
  },
  { kind: 'system', code: 'transferring', text: 'Transferring…', at: 4 },
];

const buildCall = ({ live = {}, ...overrides } = {}) => ({
  id: 7,
  provider: 'pathors',
  status: 'in-progress',
  acceptedByAgentId: null,
  startedAt: secondsAgo(102),
  live: {
    seq: 1,
    turns: 6,
    interruptions: 1,
    transferFailed: false,
    transcript,
    ...live,
  },
  ...overrides,
});

const mountMonitor = call => mount(PathorsLiveMonitor, { props: { call } });

const stat = (wrapper, key) =>
  wrapper.find(`[data-test-id="live-stat-${key}"]`);

describe('PathorsLiveMonitor', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('shows the running time, turns and interruptions', () => {
    const wrapper = mountMonitor(buildCall());

    expect(stat(wrapper, 'duration').text()).toContain('01:42');
    expect(stat(wrapper, 'turns').text()).toContain('6');
    expect(stat(wrapper, 'interruptions').text()).toContain('1');
    expect(wrapper.findAll('[data-test-id="live-alert"]')).toHaveLength(0);
  });

  it('ticks the call time on the client', async () => {
    const wrapper = mountMonitor(buildCall());

    vi.advanceTimersByTime(3000);
    await nextTick();

    expect(stat(wrapper, 'duration').text()).toContain('01:45');
  });

  it('shows one banner per alert and marks the cells over their threshold', () => {
    const wrapper = mountMonitor(
      buildCall({
        startedAt: secondsAgo(320),
        live: { transferFailed: true, interruptions: 5, turns: 21 },
      })
    );

    const banners = wrapper
      .findAll('[data-test-id="live-alert"]')
      .map(banner => banner.text());
    expect(banners).toHaveLength(4);
    expect(banners[0]).toContain('Transfer failed');
    expect(banners[1]).toContain('Interrupted 5 times');
    expect(banners[2]).toContain('Over 5 min');
    expect(banners[3]).toContain('Over 20 turns');
    ['duration', 'turns', 'interruptions'].forEach(key => {
      expect(stat(wrapper, key).attributes('data-over')).toBe('true');
    });
  });

  it('renders caller lines left, AI lines right and system lines centered', () => {
    const wrapper = mountMonitor(buildCall());

    const user = wrapper.find('[data-test-id="live-user-line"]');
    const assistant = wrapper.find('[data-test-id="live-assistant-line"]');
    const systemLines = wrapper.findAll('[data-test-id="live-system-line"]');

    expect(user.classes()).toContain('self-start');
    expect(user.text()).toContain('I want a private room');
    expect(assistant.classes()).toContain('self-end');
    expect(assistant.text()).toContain('Interrupted');
    expect(systemLines.map(line => line.text())).toEqual([
      'Transfer failed: line busy',
      'Transferring…',
    ]);
    expect(systemLines[0].classes()).toContain('text-n-ruby-11');
    expect(systemLines[1].classes()).not.toContain('text-n-ruby-11');
  });

  it('counts only spoken lines in the transcript header', () => {
    const wrapper = mountMonitor(buildCall());

    expect(wrapper.find('[data-test-id="live-transcript-count"]').text()).toBe(
      '2 messages'
    );
  });

  it('hides the transcript box until the first line arrives', () => {
    const wrapper = mountMonitor(buildCall({ live: { transcript: [] } }));

    expect(wrapper.find('[data-test-id="live-transcript"]').exists()).toBe(
      false
    );
  });

  it('follows new lines unless the reader scrolled up', async () => {
    const call = buildCall();
    const wrapper = mountMonitor(call);
    const box = wrapper.find('[data-test-id="live-transcript"]');
    const el = box.element;
    Object.defineProperty(el, 'scrollHeight', {
      configurable: true,
      value: 1000,
    });
    Object.defineProperty(el, 'clientHeight', {
      configurable: true,
      value: 230,
    });

    el.scrollTop = 770;
    await box.trigger('scroll');
    await wrapper.setProps({
      call: { ...call, live: { ...call.live, seq: 2 } },
    });
    await nextTick();
    expect(el.scrollTop).toBe(1000);

    el.scrollTop = 100;
    await box.trigger('scroll');
    await wrapper.setProps({
      call: { ...call, live: { ...call.live, seq: 3 } },
    });
    await nextTick();
    expect(el.scrollTop).toBe(100);
  });
});
