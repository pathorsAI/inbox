import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

// public/sw.js is served as is, outside the bundle; run it against a fake
// worker scope to check the Pathors call notifications it shows.
const SOURCE = readFileSync(resolve('public/sw.js'), 'utf8');

const payload = (overrides = {}) => ({
  tag: 'pathors-call-7',
  title: '陳先生：被打斷 4 次',
  body: '訂位專線',
  level: 'amber',
  signature: 'amber|陳先生：被打斷 4 次|訂位專線',
  actions: [
    { action: 'take-over', title: '前往接手' },
    { action: 'dismiss', title: '略過' },
  ],
  data: { callId: 7, accountId: 3, url: '/app/accounts/3/calls/need?call=7' },
  ...overrides,
});

const windowClient = (path, overrides = {}) => ({
  url: `https://inbox.pathors.com${path}`,
  frameType: 'top-level',
  focused: false,
  focus: vi.fn(async () => {}),
  postMessage: vi.fn(),
  ...overrides,
});

const loadWorker = () => {
  const handlers = {};
  let shown = [];
  const registration = {
    getNotifications: vi.fn(async ({ tag }) =>
      shown.filter(item => item.tag === tag)
    ),
    showNotification: vi.fn(async (title, options) => {
      const item = { title, ...options, close: vi.fn() };
      item.close.mockImplementation(() => {
        shown = shown.filter(other => other !== item);
      });
      shown = [...shown.filter(other => other.tag !== options.tag), item];
    }),
  };
  const windows = [];
  const clients = {
    matchAll: vi.fn(async () => windows),
    openWindow: vi.fn(async () => {}),
  };
  const self = {
    registration,
    addEventListener: (type, handler) => {
      handlers[type] = handler;
    },
  };
  // eslint-disable-next-line no-new-func
  new Function('self', 'clients', SOURCE)(self, clients);

  const dispatch = async (type, event) => {
    const pending = [];
    handlers[type]({ ...event, waitUntil: promise => pending.push(promise) });
    await Promise.all(pending);
  };

  return {
    windows,
    clients,
    registration,
    shown: () => shown,
    notify: item =>
      dispatch('message', {
        data: { type: 'pathors-call:notify', payload: item },
      }),
    close: tags =>
      dispatch('message', { data: { type: 'pathors-call:close', tags } }),
    closeByHand: notification =>
      dispatch('notificationclose', { notification }),
    click: (notification, action = '') =>
      dispatch('notificationclick', { notification, action }),
  };
};

describe('sw.js Pathors call notifications', () => {
  it('shows a call that stays up, with its buttons', async () => {
    const worker = loadWorker();
    worker.windows.push(windowClient('/app/accounts/3/dashboard'));

    await worker.notify(payload());

    expect(worker.registration.showNotification).toHaveBeenCalledWith(
      '陳先生：被打斷 4 次',
      expect.objectContaining({
        tag: 'pathors-call-7',
        requireInteraction: true,
        renotify: false,
        actions: payload().actions,
        data: expect.objectContaining({ pathorsCall: true, level: 'amber' }),
      })
    );
  });

  it('shows nothing while a dashboard window is in front', async () => {
    const worker = loadWorker();
    worker.windows.push(
      windowClient('/app/accounts/3/dashboard', { focused: true })
    );

    await worker.notify(payload());

    expect(worker.registration.showNotification).not.toHaveBeenCalled();
  });

  it('ignores a focused widget frame on some other site', async () => {
    const worker = loadWorker();
    worker.windows.push(
      windowClient('/widget?website_token=x', {
        focused: true,
        frameType: 'nested',
      })
    );

    await worker.notify(payload());

    expect(worker.registration.showNotification).toHaveBeenCalledTimes(1);
  });

  it('shows the same text once however many tabs send it', async () => {
    const worker = loadWorker();

    await Promise.all([worker.notify(payload()), worker.notify(payload())]);

    expect(worker.registration.showNotification).toHaveBeenCalledTimes(1);
  });

  it('updates quietly, and alerts again when the call turns red', async () => {
    const worker = loadWorker();
    await worker.notify(payload());

    await worker.notify(
      payload({ title: '陳先生：被打斷 5 次', signature: 'amber|5' })
    );
    expect(worker.registration.showNotification).toHaveBeenLastCalledWith(
      '陳先生：被打斷 5 次',
      expect.objectContaining({ renotify: false })
    );

    await worker.notify(
      payload({
        level: 'red',
        title: '陳先生：AI 請求支援',
        signature: 'red|1',
      })
    );
    expect(worker.registration.showNotification).toHaveBeenLastCalledWith(
      '陳先生：AI 請求支援',
      expect.objectContaining({ renotify: true })
    );
  });

  it('keeps a call the agent closed away until it turns red', async () => {
    const worker = loadWorker();
    await worker.notify(payload());
    const [notification] = worker.shown();
    notification.close();
    await worker.closeByHand(notification);

    await worker.notify(payload({ signature: 'amber|5' }));
    expect(worker.registration.showNotification).toHaveBeenCalledTimes(1);

    await worker.notify(payload({ level: 'red', signature: 'red|1' }));
    expect(worker.registration.showNotification).toHaveBeenCalledTimes(2);
  });

  it('closes the calls the dashboard says are handled', async () => {
    const worker = loadWorker();
    await worker.notify(payload());

    await worker.close(['pathors-call-7']);

    expect(worker.shown()).toEqual([]);
  });

  it('brings the account’s tab forward and opens the call', async () => {
    const worker = loadWorker();
    const other = windowClient('/app/accounts/9/dashboard');
    const mine = windowClient('/app/accounts/3/conversations');
    worker.windows.push(other, mine);
    await worker.notify(payload());
    const [notification] = worker.shown();

    await worker.click(notification);

    expect(notification.close).toHaveBeenCalled();
    expect(mine.focus).toHaveBeenCalled();
    expect(mine.postMessage).toHaveBeenCalledWith({
      type: 'pathors-call:open',
      callId: 7,
    });
    expect(other.focus).not.toHaveBeenCalled();
  });

  it('opens a new tab on the call when no tab has that account', async () => {
    const worker = loadWorker();
    worker.windows.push(windowClient('/app/accounts/9/dashboard'));
    await worker.notify(payload());

    await worker.click(worker.shown()[0], 'take-over');

    expect(worker.clients.openWindow).toHaveBeenCalledWith(
      '/app/accounts/3/calls/need?call=7'
    );
  });

  it('passes 略過 to the tab without bringing it forward', async () => {
    const worker = loadWorker();
    const mine = windowClient('/app/accounts/3/dashboard');
    worker.windows.push(mine);
    await worker.notify(payload());

    await worker.click(worker.shown()[0], 'dismiss');

    expect(mine.focus).not.toHaveBeenCalled();
    expect(mine.postMessage).toHaveBeenCalledWith({
      type: 'pathors-call:dismiss',
      callId: 7,
    });
  });

  it('still opens Chatwoot’s own push notifications by their url', async () => {
    const worker = loadWorker();

    await worker.click({ data: { url: '/app/accounts/3/conversations/5' } });

    expect(worker.clients.openWindow).toHaveBeenCalledWith(
      '/app/accounts/3/conversations/5'
    );
  });
});
