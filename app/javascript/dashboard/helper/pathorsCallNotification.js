import { frontendURL } from 'dashboard/helper/URLHelper';
import { attentionLevelOf } from 'dashboard/helper/pathorsCallState';
import { PATHORS_ALERT_LEVEL } from 'dashboard/helper/pathorsLiveCall';

/**
 * Desktop notifications for the calls in 需要處理, for the agent who is not
 * looking at the dashboard. They are shown through the service worker
 * (public/sw.js) rather than `new Notification()`, so that they can carry
 * buttons, stay up until handled, and bring the tab forward when clicked.
 *
 * The message types, action names and notification `data` below are the
 * contract with sw.js, which cannot import this file: change both together.
 */

// The agent's on/off switch, kept with Chatwoot's own push preferences
// (NotificationSetting::PATHORS_PUSH_FLAGS).
export const PATHORS_CALL_NOTIFY_FLAG = 'push_pathors_call_attention';

export const PATHORS_CALL_SW_MESSAGE = Object.freeze({
  // dashboard → sw
  NOTIFY: 'pathors-call:notify',
  CLOSE: 'pathors-call:close',
  // sw → dashboard
  OPEN: 'pathors-call:open',
  DISMISS: 'pathors-call:dismiss',
});

export const PATHORS_CALL_NOTIFY_ACTION = Object.freeze({
  TAKE_OVER: 'take-over',
  DISMISS: 'dismiss',
});

/** @param {number} callId */
export const callNotificationTag = callId => `pathors-call-${callId}`;

/**
 * Notifications need both the Notification API and a service worker to show
 * them; without either there is nothing to switch on.
 */
export const isDesktopNotifySupported = () =>
  'Notification' in globalThis &&
  'serviceWorker' in (globalThis.navigator ?? {});

/** `granted`, `denied` or `default`; `unsupported` when there is no API. */
export const notificationPermission = () =>
  isDesktopNotifySupported()
    ? globalThis.Notification.permission
    : 'unsupported';

/**
 * What a call in 需要處理 is about, as a heading: the red state's own label
 * (AI 請求支援, 轉接失敗), or for an amber call its first alert (被打斷 5 次)
 * with that alert's hint (客人一直插話，可能不耐煩).
 * @param {Object} state from primaryCallState
 * @returns {{ level: string|null, labelKey: string, labelParams?: Object,
 *   hintKey?: string, hintParams?: Object }}
 */
export const attentionHeadline = state => {
  const level = attentionLevelOf(state);
  const [alert] = state.alerts || [];
  if (level === PATHORS_ALERT_LEVEL.AMBER && alert) {
    return {
      level,
      labelKey: alert.labelKey,
      labelParams: alert.params,
      hintKey: alert.hintKey,
      hintParams: alert.params,
    };
  }
  return { level, labelKey: state.labelKey, labelParams: state.labelParams };
};

/**
 * The NOTIFY payload for one call. `signature` is what sw.js compares to
 * decide whether anything changed since the last one it showed.
 * @param {{ callId: number, accountId: number, level: string,
 *   heading: string, caller: string, number: string, line: string,
 *   detail: string, actionTitles: { takeOver: string, dismiss: string } }} parts
 *   texts already translated; `caller` may be empty (then the number names it)
 */
export const buildCallNotification = ({
  callId,
  accountId,
  level,
  heading,
  caller,
  number,
  line,
  detail,
  actionTitles,
}) => {
  const who = caller || number;
  const title = [who, heading].filter(Boolean).join('：');
  const body = [
    [line, caller ? number : ''].filter(Boolean).join(' · '),
    detail,
  ]
    .filter(Boolean)
    .join('\n');
  return {
    tag: callNotificationTag(callId),
    title,
    body,
    level,
    signature: `${level}|${title}|${body}`,
    actions: [
      {
        action: PATHORS_CALL_NOTIFY_ACTION.TAKE_OVER,
        title: actionTitles.takeOver,
      },
      {
        action: PATHORS_CALL_NOTIFY_ACTION.DISMISS,
        title: actionTitles.dismiss,
      },
    ],
    data: {
      callId,
      accountId,
      url: frontendURL(`accounts/${accountId}/calls/need`, { call: callId }),
    },
  };
};
