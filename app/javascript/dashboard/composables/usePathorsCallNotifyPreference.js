import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import wootConstants from 'dashboard/constants/globals';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import {
  PATHORS_CALL_NOTIFY_FLAG,
  isDesktopNotifySupported,
  notificationPermission,
} from 'dashboard/helper/pathorsCallNotification';

const [ONLINE] = wootConstants.AVAILABILITY_STATUS_KEYS;

// One fetch of the notification settings, however many surfaces ask at once.
let settingsRequest = null;

/**
 * The agent's 通話桌面通知 switch, shared by the notification preferences
 * row, the avatar menu and the dashboard prompt: their push preference, the
 * browser permission behind it, and whether they are on duty (online).
 *
 * Turning it on asks the browser for permission. A refusal still leaves it
 * on, because the flashing tab title and the sound need no permission, and
 * the agent is told how to allow notifications again.
 */
export function usePathorsCallNotifyPreference() {
  const { t } = useI18n();
  const store = useStore();
  const accountId = useMapGetter('getCurrentAccountId');
  const isFeatureEnabledonAccount = useMapGetter(
    'accounts/isFeatureEnabledonAccount'
  );
  const availability = useMapGetter('getCurrentUserAvailability');
  const emailFlags = useMapGetter(
    'userNotificationSettings/getSelectedEmailFlags'
  );
  const pushFlags = useMapGetter(
    'userNotificationSettings/getSelectedPushFlags'
  );

  const permission = ref(notificationPermission());
  const refreshPermission = () => {
    permission.value = notificationPermission();
  };

  const isSupported = isDesktopNotifySupported();
  // Calls exist only on accounts with voice on.
  const isAvailable = computed(
    () =>
      !!accountId.value &&
      isFeatureEnabledonAccount.value(
        accountId.value,
        FEATURE_FLAGS.CHANNEL_VOICE
      )
  );
  const isLoaded = computed(() => Array.isArray(pushFlags.value));
  const isOn = computed(
    () => isLoaded.value && pushFlags.value.includes(PATHORS_CALL_NOTIFY_FLAG)
  );
  const isOnDuty = computed(() => availability.value === ONLINE);
  const isBlocked = computed(() => permission.value === 'denied');

  const ensureLoaded = () => {
    if (isLoaded.value) return Promise.resolve();
    settingsRequest ||= store
      .dispatch('userNotificationSettings/get')
      .finally(() => {
        settingsRequest = null;
      });
    return settingsRequest;
  };

  // The endpoint replaces both lists, so the rest of them go back unchanged.
  const save = async enabled => {
    await ensureLoaded();
    if (!isLoaded.value) {
      useAlert(t('CALLS_PAGE.NOTIFY.SAVE_FAILED'));
      return;
    }
    const others = pushFlags.value.filter(
      flag => flag !== PATHORS_CALL_NOTIFY_FLAG
    );
    try {
      await store.dispatch('userNotificationSettings/update', {
        selectedEmailFlags: emailFlags.value || [],
        selectedPushFlags: enabled
          ? [...others, PATHORS_CALL_NOTIFY_FLAG]
          : others,
      });
    } catch {
      useAlert(t('CALLS_PAGE.NOTIFY.SAVE_FAILED'));
    }
  };

  const enable = async () => {
    if (!isSupported) return;
    if (permission.value === 'default') {
      await globalThis.Notification.requestPermission();
      refreshPermission();
    }
    await save(true);
    if (isBlocked.value) useAlert(t('CALLS_PAGE.NOTIFY.BLOCKED'));
  };

  /** @param {boolean} value */
  const setOn = value => (value ? enable() : save(false));

  // The agent can change the permission in the site settings at any time.
  onMounted(() => globalThis.addEventListener('focus', refreshPermission));
  onBeforeUnmount(() =>
    globalThis.removeEventListener('focus', refreshPermission)
  );

  return {
    isAvailable,
    isSupported,
    isLoaded,
    isOn,
    isOnDuty,
    isBlocked,
    permission,
    ensureLoaded,
    setOn,
  };
}
