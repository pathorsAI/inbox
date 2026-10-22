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
// Every open dashboard tab runs this; a call's alert is claimed in
// localStorage once one tab has rung it, so the others stay quiet. A claim
// lasts while the call stays in 需要處理: it is released when the call leaves,
// so the next time it needs someone (a retried transfer failing again) rings.
const ALERT_CLAIM_PREFIX = 'pathors-call-alert:';
const ALERT_CLAIM_TTL_MS = 24 * 60 * 60 * 1000;
const ALERT_LEVELS = [PATHORS_ALERT_LEVEL.RED, PATHORS_ALERT_LEVEL.AMBER];

const claimStorageKey = key => `${ALERT_CLAIM_PREFIX}${key}`;

const isAlertClaimed = key => {
  try {
    return !!globalThis.localStorage.getItem(claimStorageKey(key));
  } catch {
    // Storage blocked: ring, a second tab ringing too is the lesser harm.
    return false;
  }
};

const claimAlert = key => {
  try {
    globalThis.localStorage.setItem(claimStorageKey(key), String(Date.now()));
  } catch {
    // As above.
  }
};

const releaseAlertClaims = callId => {
  try {
    ALERT_LEVELS.forEach(level =>
      globalThis.localStorage.removeItem(claimStorageKey(`${callId}:${level}`))
    );
  } catch {
    // As above.
  }
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

// Claimed only once the sound plays: a background tab without the right to
// play audio rejects play(), and then another tab may still ring it.
const ringOnce = key => {
  if (isAlertClaimed(key)) return;
  try {
    new Audio(ALERT_SOUND_URL)
      .play()
      .then(() => claimAlert(key))
      .catch(() => {});
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
      if ((isNew || escalated) && !isWindowFocused()) {
        ringOnce(`${callId}:${item.level}`);
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
        tags: gone.map(callId => callNotificationTag(callId)),
      });
      gone.forEach(callId => {
        known.delete(callId);
        releaseAlertClaims(callId);
      });
    }
  };

  // Immediate: calls already waiting when the dashboard loads count as new.
  watch(notifications, sync, { immediate: true });
  // Hands every waiting call to the worker again; it skips what is already
  // on screen.
  const resend = () => {
    known.forEach(entry => {
      entry.signature = null;
    });
    sync(notifications.value);
  };
  // Allowing notifications later shows what is already waiting.
  watch(preference.permission, resend);
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
  // The worker shows nothing while the dashboard is in front, so a call that
  // came in then and is still waiting reaches the desktop once it is not.
  watch(isFocused, focused => {
    if (!focused) resend();
  });
  let flashTimer = null;
  let restingTitle = '';
  let flashText = '';
  const stopFlashing = () => {
    if (!flashTimer) return;
    clearInterval(flashTimer);
    flashTimer = null;
    const { document } = globalThis;
    if (flashText && document.title === flashText)
      document.title = restingTitle;
    flashText = '';
  };
  const startFlashing = () => {
    if (flashTimer) return;
    let showCall = false;
    flashTimer = setInterval(() => {
      const { document } = globalThis;
      // The app may retitle the page meanwhile (a route change); follow it.
      if (!flashText || document.title !== flashText) {
        restingTitle = document.title;
      }
      showCall = !showCall;
      const [first] = notifications.value;
      flashText =
        showCall && first
          ? t('CALLS_PAGE.NOTIFY.TITLE_FLASH', { title: first.title })
          : '';
      document.title = flashText || restingTitle;
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
