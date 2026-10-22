/* eslint-disable no-restricted-globals, no-console */
/* globals clients */

// Pathors: desktop notifications for live calls that need a human, asked for
// by the dashboard (components-next/Calls/usePathorsCallNotifications.js). The
// message types, action names and notification data must match
// dashboard/helper/pathorsCallNotification.js, which this file cannot import.
const PATHORS_CALL = {
  NOTIFY: 'pathors-call:notify',
  CLOSE: 'pathors-call:close',
  OPEN: 'pathors-call:open',
  DISMISS: 'pathors-call:dismiss',
  ACTION_DISMISS: 'dismiss',
  RED: 'red',
};

// Every open dashboard tab sends the same calls; one at a time, so two tabs
// never show the same notification twice.
let pathorsCallQueue = Promise.resolve();
// tag → level of the notifications the agent closed by hand. Such a call
// comes back only when it gets worse (amber to red), not on every change.
// Lost when the browser stops the worker, which costs one more notification.
const pathorsClosedLevels = new Map();
// tag → when this worker closed that notification itself (a handled call, a
// click). Some browsers fire notificationclose for those too; only a close by
// hand may hold a call back.
const pathorsSelfClosedAt = new Map();
const PATHORS_SELF_CLOSE_WINDOW_MS = 5000;

const closeOwnPathorsCall = notification => {
  pathorsSelfClosedAt.set(notification.tag, Date.now());
  notification.close();
};

const pathorsDashboardWindows = () =>
  clients
    .matchAll({ type: 'window', includeUncontrolled: true })
    .then(windowClients =>
      windowClients.filter(
        client =>
          client.frameType !== 'nested' &&
          new URL(client.url).pathname.startsWith('/app/')
      )
    );

const showPathorsCall = async payload => {
  const windows = await pathorsDashboardWindows();
  // The agent is looking at the dashboard: the in-page alerts are enough.
  if (windows.some(client => client.focused)) return;

  const [existing] = await self.registration.getNotifications({
    tag: payload.tag,
  });
  const previous = existing?.data;
  if (previous?.signature === payload.signature) return;

  const closedLevel = pathorsClosedLevels.get(payload.tag);
  const lastLevel = previous?.level ?? closedLevel;
  const escalated =
    payload.level === PATHORS_CALL.RED &&
    lastLevel !== undefined &&
    lastLevel !== PATHORS_CALL.RED;
  if (closedLevel !== undefined && !escalated) return;

  pathorsClosedLevels.delete(payload.tag);
  await self.registration.showNotification(payload.title, {
    tag: payload.tag,
    body: payload.body,
    icon: '/android-icon-192x192.png',
    requireInteraction: true,
    // A change to a call already on screen updates it quietly; a call that
    // turned red alerts again.
    renotify: !!existing && escalated,
    actions: payload.actions,
    data: {
      ...payload.data,
      pathorsCall: true,
      level: payload.level,
      signature: payload.signature,
    },
  });
};

const closePathorsCalls = tags =>
  Promise.all(
    tags.map(async tag => {
      // The call is handled: forget it was ever closed by hand.
      pathorsClosedLevels.delete(tag);
      const notifications = await self.registration.getNotifications({ tag });
      notifications.forEach(closeOwnPathorsCall);
    })
  );

const openPathorsCall = async (data, action) => {
  const windows = await pathorsDashboardWindows();
  // A tab on another account would open the call under the wrong account.
  const target = windows.find(client =>
    new URL(client.url).pathname.startsWith(`/app/accounts/${data.accountId}/`)
  );

  // With no dashboard tab on the account, 略過 only takes the notification
  // away; the call stays unmuted and shows again in the next tab opened.
  if (action === PATHORS_CALL.ACTION_DISMISS) {
    target?.postMessage({ type: PATHORS_CALL.DISMISS, callId: data.callId });
    return;
  }
  if (target) {
    await target.focus();
    target.postMessage({ type: PATHORS_CALL.OPEN, callId: data.callId });
    return;
  }
  await clients.openWindow(data.url);
};

const queuePathorsCall = (event, work) => {
  pathorsCallQueue = pathorsCallQueue
    .then(work)
    .catch(error => console.warn('[pathors-call]', error));
  event.waitUntil(pathorsCallQueue);
};

self.addEventListener('message', event => {
  const { type, payload, tags } = event.data || {};
  if (type === PATHORS_CALL.NOTIFY) {
    queuePathorsCall(event, () => showPathorsCall(payload));
  } else if (type === PATHORS_CALL.CLOSE) {
    queuePathorsCall(event, () => closePathorsCalls(tags || []));
  }
});

self.addEventListener('notificationclose', event => {
  const { notification } = event;
  if (!notification.data?.pathorsCall) return;
  const selfClosedAt = pathorsSelfClosedAt.get(notification.tag);
  pathorsSelfClosedAt.delete(notification.tag);
  if (
    selfClosedAt &&
    Date.now() - selfClosedAt < PATHORS_SELF_CLOSE_WINDOW_MS
  ) {
    return;
  }
  pathorsClosedLevels.set(notification.tag, notification.data.level);
});

self.addEventListener('push', event => {
  let notification = event.data && event.data.json();

  event.waitUntil(
    self.registration.showNotification(notification.title, {
      tag: notification.tag,
      data: {
        url: notification.url,
      },
    })
  );
});

self.addEventListener('notificationclick', event => {
  let notification = event.notification;

  if (notification.data?.pathorsCall) {
    closeOwnPathorsCall(notification);
    event.waitUntil(openPathorsCall(notification.data, event.action));
    return;
  }

  event.waitUntil(
    clients.matchAll({ type: 'window' }).then(windowClients => {
      let matchingWindowClients = windowClients.filter(
        client => client.url === notification.data.url
      );

      if (matchingWindowClients.length) {
        let firstWindow = matchingWindowClients[0];
        if (firstWindow && 'focus' in firstWindow) {
          firstWindow.focus();
          return;
        }
      }
      if (clients.openWindow) {
        clients.openWindow(notification.data.url);
      }
    })
  );
});
