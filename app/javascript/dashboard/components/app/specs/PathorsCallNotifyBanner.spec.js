import { ref } from 'vue';
import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import PathorsCallNotifyBanner from '../PathorsCallNotifyBanner.vue';

withFullI18n('zh_TW');

const { preference, ui } = vi.hoisted(() => ({
  preference: {},
  ui: { settings: null, update: null },
}));

vi.mock('dashboard/composables/usePathorsCallNotifyPreference', () => ({
  usePathorsCallNotifyPreference: () => preference,
}));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    uiSettings: ui.settings,
    updateUISettings: ui.update,
  }),
}));

const banner = wrapper =>
  wrapper.find('[data-test-id="pathors-call-notify-banner"]');

describe('PathorsCallNotifyBanner', () => {
  beforeEach(() => {
    Object.assign(preference, {
      isAvailable: ref(true),
      isSupported: true,
      isLoaded: ref(true),
      isOn: ref(false),
      isOnDuty: ref(true),
      ensureLoaded: vi.fn(),
      setOn: vi.fn(),
    });
    ui.settings = ref({});
    ui.update = vi.fn();
  });

  it('asks an online agent who has not decided yet', () => {
    const wrapper = mount(PathorsCallNotifyBanner);

    expect(preference.ensureLoaded).toHaveBeenCalled();
    expect(banner(wrapper).text()).toContain(
      '你現在是「線上」。需要處理的通話要在桌面跳通知嗎？'
    );
  });

  it('turns it on from the prompt', async () => {
    const wrapper = mount(PathorsCallNotifyBanner);

    await wrapper
      .find('[data-test-id="pathors-call-notify-enable"]')
      .trigger('click');

    expect(preference.setOn).toHaveBeenCalledWith(true);
  });

  it('remembers 不用 for good', async () => {
    const wrapper = mount(PathorsCallNotifyBanner);

    await wrapper
      .find('[data-test-id="pathors-call-notify-decline"]')
      .trigger('click');

    expect(ui.update).toHaveBeenCalledWith({
      pathors_call_notify_prompt_dismissed: true,
    });
  });

  it.each([
    [
      'already on',
      () => {
        preference.isOn.value = true;
      },
    ],
    [
      'busy',
      () => {
        preference.isOnDuty.value = false;
      },
    ],
    [
      'declined before',
      () => {
        ui.settings.value = { pathors_call_notify_prompt_dismissed: true };
      },
    ],
    [
      'without voice calls',
      () => {
        preference.isAvailable.value = false;
      },
    ],
    [
      'in a browser without notifications',
      () => {
        preference.isSupported = false;
      },
    ],
    [
      'before the settings load',
      () => {
        preference.isLoaded.value = false;
      },
    ],
  ])('stays away when %s', (_, arrange) => {
    arrange();
    const wrapper = mount(PathorsCallNotifyBanner);

    expect(banner(wrapper).exists()).toBe(false);
  });
});
