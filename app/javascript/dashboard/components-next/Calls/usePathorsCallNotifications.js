import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useClock } from 'dashboard/composables/useClock';
import { usePathorsCallNotifyPreference } from 'dashboard/composables/usePathorsCallNotifyPreference';
import {
  PATHORS_CALL_SW_MESSAGE,
  attentionHeadline,
  buildCallNotification,
  callNotificationTag,
  isDesktopNotifySupported,
} from 'dashboard/helper/pathorsCallNotification';
import { PATHORS_ALERT_LEVEL } from 'dashboard/helper/pathorsLiveCall';
import { usePathorsLiveCallsStore } from 'dashboard/stores/pathorsLiveCalls';
import { callerName, callerNumber, lineName } from './constants';
import { useCallStateText } from './useCallStateText';

// Amber can come from the clock alone (a long call); minute precision is enough.
const CLOCK_TICK_MS = 15_000;
const TITLE_FLASH_MS = 1000;
const ALERT_SOUND_URL = '/audio/dashboard/bell.mp3';
// Every open dashboard tab runs this; the first to claim a call's alert in
// localStorage plays the sound, so two tabs never ring twice.
const ALERT_CLAIM_PREFIX = 'pathors-call-alert:';
const ALERT_CLAIM_TTL_MS = 24 * 60 * 60 * 1000;

const claimAlert = key => {
  try {
    const storageKey = `${ALERT_CLAIM_PREFIX}${key}`;
    if (globalThis.localStorage.getItem(storageKey)) return false;
    globalThis.localStorage.setItem(storageKey, String(Date.now()));
  } catch {
    // Storage blocked: ring, a second tab ringing too is the lesser harm.
  }
  return true;
};

const pruneAlertClaims = () => {
  try {
    const { localStorage } = globalThis;
    Object.keys(localStorage)
      .filter(key => key.startsWith(ALERT_CLAIM_PREFIX))
      .filter(
        key =>
          Date.now() - Number(localStorage.getItem(key)) > ALERT_CLAIM_TTL_MS
      )
      .forEach(key => localStorage.removeItem(key));
  } catch {
    // Nothing to tidy.
  }
};

const playAlertSound = () => {
  try {
    new Audio(ALERT_SOUND_URL).play().catch(() => {});
  } catch {
    // No audio here.
  }
};

const postToWorker = async message => {
  if (!isDesktopNotifySupported()) return;
  try {
    const { serviceWorker } = globalThis.navigator;
    if (!(await serviceWorker.getRegistration())) {
      await serviceWorker.register('/sw.js');
    }
    const registration = await serviceWorker.ready;
    registration.active?.postMessage(message);
  } catch (error) {
    // eslint-disable-next-line no-console
    console.warn('[pathors-call-notify] service worker unavailable', error);
  }
};

const isWindowFocused = () =>
  globalThis.document.visibilityState === 'visible' &&
  globalThis.document.hasFocus();

/**
 * 方案 C of #3842: while the agent is online and has 通話桌面通知 on, every
 * call that enters 需要處理 (red or amber) pops a desktop notification that
 * stays until someone takes the call, it ends, or the agent mutes it; the tab
 * title flashes and a sound plays while the dashboard is not in front.
 *
 * Only the call side lives here. public/sw.js decides whether a notification
 * actually shows (never while a dashboard window is focused, never twice for
 * the same text) and turns clicks into OPEN / DISMISS messages back.
 */
export function usePathorsCallNotifications() {
  const { t } = useI18n();
  const router = useRouter();
  const store = usePathorsLiveCallsStore();
  const accountId = useMapGetter('getCurrentAccountId');
  const getInbox = useMapGetter('inboxes/getInbox');
  const now = useClock(CLOCK_TICK_MS);
  const preference = usePathorsCallNotifyPreference();
  const { stateDetail } = useCallStateText();

  const isActive = computed(
    () =>
      preference.isAvailable.value &&
      preference.isOn.value &&
      preference.isOnDuty.value
  );

  const describe = call => {
    const headline = attentionHeadline(call.callState);
    return {
      level: headline.level,
      heading: t(headline.labelKey, headline.labelParams || {}),
      detail: headline.hintKey
        ? t(headline.hintKey, headline.hintParams || {})
        : stateDetail(call, call.callState),
      caller: callerName(call),
      number: callerNumber(call),
      line: lineName(call) || getInbox.value(call.inboxId)?.name || '',
    };
  };

  const notifications = computed(() =>
    (isActive.value ? store.attentionCallsAt(now.value) : []).map(call =>
      buildCallNotification({
        callId: call.id,
        accountId: accountId.value,
        actionTitles: {
          takeOver: t('CALLS_PAGE.ATTENTION.GO_TAKE_OVER'),
          dismiss: t('CALLS_PAGE.ATTENTION.DISMISS'),
        },
        ...describe(call),
      })
    )
  );

  // callId → the signature and level last handed to the worker.
  const known = new Map();

  const sync = list => {
    const canShow = preference.permission.value === 'granted';
    const current = new Map(list.map(item => [item.data.callId, item]));

    current.forEach((item, callId) => {
      const previous = known.get(callId);
      const isNew = !previous;
      const escalated =
        previous?.level === PATHORS_ALERT_LEVEL.AMBER &&
        item.level === PATHORS_ALERT_LEVEL.RED;
      if (
        (isNew || escalated) &&
        !isWindowFocused() &&
        claimAlert(`${callId}:${item.level}`)
      ) {
        playAlertSound();
      }
      if (canShow && previous?.signature !== item.signature) {
        postToWorker({ type: PATHORS_CALL_SW_MESSAGE.NOTIFY, payload: item });
      }
      known.set(callId, { signature: item.signature, level: item.level });
    });

    const gone = [...known.keys()].filter(callId => !current.has(callId));
    if (gone.length) {
      postToWorker({
        type: PATHORS_CALL_SW_MESSAGE.CLOSE,
        tags: gone.map(callNotificationTag),
      });
      gone.forEach(callId => known.delete(callId));
    }
  };

  // Immediate: calls already waiting when the dashboard loads count as new.
  watch(notifications, sync, { immediate: true });
  // Allowing notifications later shows what is already waiting.
  watch(preference.permission, () => {
    known.forEach(entry => {
      entry.signature = null;
    });
    sync(notifications.value);
  });
  watch(
    preference.isAvailable,
    available => {
      if (available) preference.ensureLoaded();
    },
    { immediate: true }
  );

  // The tab title flashes who is waiting while the dashboard is behind.
  const isFocused = ref(isWindowFocused());
  const updateFocus = () => {
    isFocused.value = isWindowFocused();
  };
  let flashTimer = null;
  let restingTitle = '';
  const stopFlashing = () => {
    if (!flashTimer) return;
    clearInterval(flashTimer);
    flashTimer = null;
    globalThis.document.title = restingTitle;
  };
  const startFlashing = () => {
    if (flashTimer) return;
    restingTitle = globalThis.document.title;
    let showCall = false;
    flashTimer = setInterval(() => {
      showCall = !showCall;
      const [first] = notifications.value;
      globalThis.document.title =
        showCall && first
          ? t('CALLS_PAGE.NOTIFY.TITLE_FLASH', { title: first.title })
          : restingTitle;
    }, TITLE_FLASH_MS);
  };
  watch(
    () => !isFocused.value && notifications.value.length > 0,
    shouldFlash => (shouldFlash ? startFlashing() : stopFlashing()),
    { immediate: true }
  );

  const onWorkerMessage = event => {
    const { type, callId } = event.data || {};
    if (type === PATHORS_CALL_SW_MESSAGE.OPEN) {
      router.push({
        name: 'calls_need',
        params: { accountId: accountId.value },
        query: { call: callId },
      });
      return;
    }
    if (type !== PATHORS_CALL_SW_MESSAGE.DISMISS) return;
    const item = notifications.value.find(
      entry => entry.data.callId === callId
    );
    if (!item) return;
    store.dismissAttention(callId, item.level).catch(() => {
      useAlert(t('CALLS_PAGE.ATTENTION.DISMISS_FAILED'));
    });
  };

  const FOCUS_EVENTS = ['focus', 'blur'];
  onMounted(() => {
    pruneAlertClaims();
    FOCUS_EVENTS.forEach(name =>
      globalThis.addEventListener(name, updateFocus)
    );
    globalThis.document.addEventListener('visibilitychange', updateFocus);
    globalThis.navigator.serviceWorker?.addEventListener(
      'message',
      onWorkerMessage
    );
  });
  onBeforeUnmount(() => {
    stopFlashing();
    FOCUS_EVENTS.forEach(name =>
      globalThis.removeEventListener(name, updateFocus)
    );
    globalThis.document.removeEventListener('visibilitychange', updateFocus);
    globalThis.navigator.serviceWorker?.removeEventListener(
      'message',
      onWorkerMessage
    );
  });
}
