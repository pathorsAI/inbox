import { defineComponent, h, reactive } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { useAlert } from 'dashboard/composables';
import { usePathorsCallNotifyPreference } from '../usePathorsCallNotifyPreference';

withFullI18n('zh_TW');

const { getters, dispatch } = vi.hoisted(() => ({
  getters: {},
  dispatch: vi.fn(),
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return {
    useMapGetter: key => computed(() => getters[key]),
    useStore: () => ({ dispatch }),
  };
});

const FLAG = 'push_pathors_call_attention';

let state;
const resetGetters = () => {
  state = reactive({
    voice: true,
    availability: 'online',
    email: ['email_conversation_assignment'],
    push: ['push_conversation_assignment'],
  });
  Object.defineProperties(getters, {
    getCurrentAccountId: { get: () => 1, configurable: true },
    'accounts/isFeatureEnabledonAccount': {
      get: () => () => state.voice,
      configurable: true,
    },
    getCurrentUserAvailability: {
      get: () => state.availability,
      configurable: true,
    },
    'userNotificationSettings/getSelectedEmailFlags': {
      get: () => state.email,
      configurable: true,
    },
    'userNotificationSettings/getSelectedPushFlags': {
      get: () => state.push,
      configurable: true,
    },
  });
};

const installNotification = permission => {
  globalThis.Notification = {
    permission,
    requestPermission: vi.fn(async () => globalThis.Notification.permission),
  };
};

const mountPreference = () => {
  let preference;
  mount(
    defineComponent({
      setup() {
        preference = usePathorsCallNotifyPreference();
        return () => h('div');
      },
    })
  );
  return preference;
};

describe('usePathorsCallNotifyPreference', () => {
  const { Notification } = globalThis;

  beforeAll(() => {
    Object.defineProperty(globalThis.navigator, 'serviceWorker', {
      value: {},
      configurable: true,
    });
  });
  afterAll(() => {
    delete globalThis.navigator.serviceWorker;
    globalThis.Notification = Notification;
  });

  beforeEach(() => {
    resetGetters();
    installNotification('default');
    dispatch.mockImplementation(async (action, payload) => {
      if (action === 'userNotificationSettings/update') {
        state.push = payload.selectedPushFlags;
      }
    });
  });

  it('is off until the flag is set, and on duty only while online', () => {
    const preference = mountPreference();

    expect(preference.isAvailable.value).toBe(true);
    expect(preference.isOn.value).toBe(false);
    expect(preference.isOnDuty.value).toBe(true);

    state.availability = 'busy';
    expect(preference.isOnDuty.value).toBe(false);
  });

  it('asks the browser first, then saves the flag next to the others', async () => {
    const preference = mountPreference();
    globalThis.Notification.requestPermission.mockImplementation(async () => {
      globalThis.Notification.permission = 'granted';
      return 'granted';
    });

    await preference.setOn(true);

    expect(globalThis.Notification.requestPermission).toHaveBeenCalled();
    expect(dispatch).toHaveBeenCalledWith('userNotificationSettings/update', {
      selectedEmailFlags: ['email_conversation_assignment'],
      selectedPushFlags: ['push_conversation_assignment', FLAG],
    });
    expect(preference.isOn.value).toBe(true);
    expect(useAlert).not.toHaveBeenCalled();
  });

  it('stays on when the browser refuses, and says how to allow it', async () => {
    const preference = mountPreference();
    globalThis.Notification.requestPermission.mockImplementation(async () => {
      globalThis.Notification.permission = 'denied';
      return 'denied';
    });

    await preference.setOn(true);

    expect(preference.isOn.value).toBe(true);
    expect(preference.isBlocked.value).toBe(true);
    expect(useAlert).toHaveBeenCalledWith(
      expect.stringContaining('點網址列左邊的鎖頭')
    );
  });

  it('does not ask again once the browser has answered', async () => {
    installNotification('granted');
    const preference = mountPreference();

    await preference.setOn(true);

    expect(globalThis.Notification.requestPermission).not.toHaveBeenCalled();
  });

  it('turns off by dropping only its own flag', async () => {
    state.push = ['push_conversation_assignment', FLAG];
    const preference = mountPreference();

    await preference.setOn(false);

    expect(dispatch).toHaveBeenCalledWith('userNotificationSettings/update', {
      selectedEmailFlags: ['email_conversation_assignment'],
      selectedPushFlags: ['push_conversation_assignment'],
    });
  });

  it('loads the settings before saving, so no other flag is lost', async () => {
    state.push = undefined;
    installNotification('granted');
    dispatch.mockImplementation(async (action, payload) => {
      if (action === 'userNotificationSettings/get') {
        state.push = ['push_conversation_mention'];
      } else {
        state.push = payload.selectedPushFlags;
      }
    });
    const preference = mountPreference();

    await preference.setOn(true);
    await flushPromises();

    expect(dispatch).toHaveBeenNthCalledWith(1, 'userNotificationSettings/get');
    expect(dispatch).toHaveBeenLastCalledWith(
      'userNotificationSettings/update',
      expect.objectContaining({
        selectedPushFlags: ['push_conversation_mention', FLAG],
      })
    );
  });

  it('says so when saving fails', async () => {
    installNotification('granted');
    dispatch.mockRejectedValue(new Error('offline'));
    const preference = mountPreference();

    await preference.setOn(true);

    expect(useAlert).toHaveBeenCalledWith('無法儲存通知設定');
  });
});
