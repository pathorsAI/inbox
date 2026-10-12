import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import LoginShowcase from './Index.vue';

const mountShowcase = () =>
  mount(LoginShowcase, {
    global: {
      // No messages: every lookup renders its own key.
      plugins: [
        createI18n({
          legacy: false,
          locale: 'en',
          missingWarn: false,
          fallbackWarn: false,
        }),
      ],
      // Render scene swaps immediately instead of waiting for the transition.
      stubs: { Transition: { template: '<slot />' } },
    },
  });

const visibleScene = wrapper =>
  wrapper.find('[data-testid^="showcase-scene-"]').attributes('data-testid');

const mockReducedMotion = reduced => {
  globalThis.matchMedia = vi.fn().mockReturnValue({ matches: reduced });
};

describe('LoginShowcase', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
    delete globalThis.matchMedia;
  });

  it('plays the four scenes in order and loops back to the first', async () => {
    mockReducedMotion(false);
    const wrapper = mountShowcase();

    const seen = [visibleScene(wrapper)];
    for (let step = 0; step < 4; step += 1) {
      vi.advanceTimersByTime(4500);
      // eslint-disable-next-line no-await-in-loop
      await wrapper.vm.$nextTick();
      seen.push(visibleScene(wrapper));
    }

    expect(seen).toEqual([
      'showcase-scene-CHANNELS',
      'showcase-scene-VOICE',
      'showcase-scene-REPLY',
      'showcase-scene-HANDOFF',
      'showcase-scene-CHANNELS',
    ]);
    expect(wrapper.text()).toContain('LOGIN.SHOWCASE.CHANNELS.CAPTION');
  });

  it('stays on the first scene when the viewer prefers reduced motion', async () => {
    mockReducedMotion(true);
    const wrapper = mountShowcase();

    vi.advanceTimersByTime(20000);
    await wrapper.vm.$nextTick();

    expect(visibleScene(wrapper)).toBe('showcase-scene-CHANNELS');
  });

  it('is hidden from assistive technology and stops its timer on unmount', () => {
    mockReducedMotion(false);
    const wrapper = mountShowcase();

    expect(
      wrapper.find('[data-testid="login-showcase"]').attributes('aria-hidden')
    ).toBe('true');
    wrapper.unmount();
    expect(vi.getTimerCount()).toBe(0);
  });
});
