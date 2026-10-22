import { defineComponent, h, nextTick, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import { withFullI18n } from 'test-i18n';
import PathorsCallsAPI from 'dashboard/api/pathorsCalls';
import {
  usePathorsLiveCallsStore,
  resetPathorsLiveCallsTracking,
} from 'dashboard/stores/pathorsLiveCalls';
import { usePathorsCallNotifications } from '../usePathorsCallNotifications';

withFullI18n('zh_TW');
enableAutoUnmount(afterEach);

const { push, preference } = vi.hoisted(() => ({
  push: vi.fn(),
  preference: {},
}));

vi.mock('vue-router', () => ({ useRouter: () => ({ push }) }));
vi.mock('dashboard/api/pathorsCalls', () => ({
  default: { active: vi.fn(), dismiss: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  const getters = {
    getCurrentAccountId: () => 1,
    'inboxes/getInbox': () => id => ({ id, name: `線路${id}` }),
  };
  return { useMapGetter: key => computed(getters[key]) };
});
vi.mock('dashboard/composables/usePathorsCallNotifyPreference', () => ({
  usePathorsCallNotifyPreference: () => preference,
}));

const NOW = Date.parse('2026-10-22T10:01:00Z');

const activeCall = (id, live = {}, overrides = {}) => ({
  id,
  provider: 'pathors',
  status: 'in-progress',
  conversation_id: 100 + id,
  inbox_name: '訂位專線',
  contact_name: `客人${id}`,
  started_at: '2026-10-22T10:00:00Z',
  needs_action: false,
  dismissed: false,
  live: { seq: 1, turns: 3, interruptions: 0, ...live },
  ...overrides,
});

let worker;
let workerListeners;
let focused;

const posted = type =>
  worker.postMessage.mock.calls
    .map(([message]) => message)
    .filter(message => message.type === type);

const mountNotifier = async payload => {
  PathorsCallsAPI.active.mockResolvedValue({ payload });
  await usePathorsLiveCallsStore().fetchActive();
  const wrapper = mount(
    defineComponent({
      setup() {
        usePathorsCallNotifications();
        return () => h('div');
      },
    })
  );
  await flushPromises();
  return wrapper;
};

const fromWorker = async data => {
  workerListeners.forEach(listener => listener({ data }));
  await flushPromises();
};

describe('usePathorsCallNotifications', () => {
  const { Notification } = globalThis;

  beforeAll(() => {
    Object.defineProperty(globalThis.navigator, 'serviceWorker', {
      value: {},
      configurable: true,
    });
    // The permission itself comes from the preference.
    globalThis.Notification = {};
  });
  afterAll(() => {
    delete globalThis.navigator.serviceWorker;
    globalThis.Notification = Notification;
  });

  beforeEach(() => {
    setActivePinia(createPinia());
    resetPathorsLiveCallsTracking();
    globalThis.localStorage.clear();
    vi.useFakeTimers({ now: NOW, toFake: ['Date'] });

    Object.assign(preference, {
      isAvailable: ref(true),
      isOn: ref(true),
      isOnDuty: ref(true),
      permission: ref('granted'),
      ensureLoaded: vi.fn(),
    });

    worker = { postMessage: vi.fn() };
    workerListeners = [];
    const registration = { active: worker };
    Object.assign(globalThis.navigator.serviceWorker, {
      getRegistration: vi.fn(async () => registration),
      register: vi.fn(),
      ready: Promise.resolve(registration),
      addEventListener: vi.fn((type, listener) =>
        workerListeners.push(listener)
      ),
      removeEventListener: vi.fn(),
    });

    focused = false;
    vi.spyOn(globalThis.document, 'hasFocus').mockImplementation(() => focused);
    globalThis.Audio = vi.fn(() => ({ play: vi.fn(() => Promise.resolve()) }));
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('hands every call in 需要處理 to the service worker', async () => {
    await mountNotifier([
      activeCall(1, { interruptions: 4 }),
      activeCall(
        2,
        {
          attention: { takeover_request: { reason: 'cannot_hear', at: NOW } },
        },
        { needs_action: true }
      ),
      activeCall(3),
    ]);

    const notified = posted('pathors-call:notify').map(
      ({ payload }) => payload
    );
    expect(notified.map(payload => payload.tag)).toEqual([
      'pathors-call-2',
      'pathors-call-1',
    ]);
    expect(notified[0]).toMatchObject({
      title: '客人2：AI 請求支援',
      level: 'red',
      data: { url: '/app/accounts/1/calls/need?call=2' },
    });
    expect(notified[1]).toMatchObject({
      title: '客人1：被打斷 4 次',
      body: '訂位專線\n客人一直插話，可能不耐煩',
      level: 'amber',
    });
  });

  it('sends a call again only when what it says changes', async () => {
    await mountNotifier([activeCall(1, { interruptions: 4 })]);
    const store = usePathorsLiveCallsStore();

    store.handleLiveUpdated({
      id: 1,
      live: { seq: 2, turns: 4, interruptions: 4 },
    });
    await flushPromises();
    expect(posted('pathors-call:notify')).toHaveLength(1);

    store.handleLiveUpdated({
      id: 1,
      live: { seq: 3, turns: 5, interruptions: 5 },
    });
    await flushPromises();
    const notified = posted('pathors-call:notify');
    expect(notified).toHaveLength(2);
    expect(notified[1].payload.title).toBe('客人1：被打斷 5 次');
  });

  it('closes a call’s notification once someone takes it', async () => {
    await mountNotifier([activeCall(1, { interruptions: 4 })]);

    usePathorsLiveCallsStore().handleLiveUpdated({
      id: 1,
      live: { seq: 2, interruptions: 4 },
      accepted_by_agent_id: 9,
    });
    await flushPromises();

    expect(posted('pathors-call:close')).toEqual([
      { type: 'pathors-call:close', tags: ['pathors-call-1'] },
    ]);
  });

  it('stops while the agent is not online, closing what is up', async () => {
    await mountNotifier([activeCall(1, { interruptions: 4 })]);

    preference.isOnDuty.value = false;
    await flushPromises();

    expect(posted('pathors-call:close')).toHaveLength(1);
    usePathorsLiveCallsStore().handleLiveUpdated({
      id: 1,
      live: { seq: 2, interruptions: 6 },
    });
    await flushPromises();
    expect(posted('pathors-call:notify')).toHaveLength(1);
  });

  it('sends nothing until the browser allows it, then what is waiting', async () => {
    preference.permission.value = 'denied';
    await mountNotifier([activeCall(1, { interruptions: 4 })]);
    expect(posted('pathors-call:notify')).toHaveLength(0);

    preference.permission.value = 'granted';
    await flushPromises();
    expect(posted('pathors-call:notify')).toHaveLength(1);
  });

  it('rings once per call across tabs, and not while the dashboard is in front', async () => {
    globalThis.localStorage.setItem('pathors-call-alert:2:amber', String(NOW));
    await mountNotifier([
      activeCall(1, { interruptions: 4 }),
      activeCall(2, { interruptions: 4 }),
    ]);
    expect(globalThis.Audio).toHaveBeenCalledTimes(1);

    focused = true;
    globalThis.dispatchEvent(new Event('focus'));
    usePathorsLiveCallsStore().handleLiveUpdated({
      id: 3,
      live: { seq: 1, interruptions: 4 },
    });
    PathorsCallsAPI.active.mockResolvedValue({
      payload: [
        activeCall(1, { interruptions: 4 }),
        activeCall(2, { interruptions: 4 }),
        activeCall(3, { interruptions: 4 }),
      ],
    });
    await usePathorsLiveCallsStore().fetchActive();
    await flushPromises();
    expect(globalThis.Audio).toHaveBeenCalledTimes(1);
  });

  it('rings again when a call comes back to 需要處理 later', async () => {
    await mountNotifier([activeCall(1, { interruptions: 4 })]);
    await flushPromises();
    const store = usePathorsLiveCallsStore();

    store.handleLiveUpdated({ id: 1, live: { seq: 2, interruptions: 0 } });
    await flushPromises();
    store.handleLiveUpdated({ id: 1, live: { seq: 3, interruptions: 4 } });
    await flushPromises();

    expect(globalThis.Audio).toHaveBeenCalledTimes(2);
  });

  it('leaves the alert to another tab when this one may not play sound', async () => {
    globalThis.Audio = vi.fn(() => ({
      play: vi.fn(() => Promise.reject(new Error('NotAllowedError'))),
    }));
    await mountNotifier([activeCall(1, { interruptions: 4 })]);
    await flushPromises();

    expect(globalThis.localStorage.getItem('pathors-call-alert:1:amber')).toBe(
      null
    );
  });

  it('hands calls to the worker again when the dashboard goes behind', async () => {
    focused = true;
    await mountNotifier([activeCall(1, { interruptions: 4 })]);
    expect(posted('pathors-call:notify')).toHaveLength(1);

    focused = false;
    globalThis.dispatchEvent(new Event('blur'));
    await flushPromises();

    expect(posted('pathors-call:notify')).toHaveLength(2);
  });

  it('rings again when an amber call turns red', async () => {
    await mountNotifier([activeCall(1, { interruptions: 4 })]);

    usePathorsLiveCallsStore().handleLiveUpdated({
      id: 1,
      live: {
        seq: 2,
        interruptions: 4,
        attention: { takeover_request: { reason: 'looping', at: NOW } },
      },
      needs_action: true,
    });
    await flushPromises();

    expect(globalThis.Audio).toHaveBeenCalledTimes(2);
  });

  it('opens the call the agent clicked', async () => {
    await mountNotifier([activeCall(1, { interruptions: 4 })]);

    await fromWorker({ type: 'pathors-call:open', callId: 1 });

    expect(push).toHaveBeenCalledWith({
      name: 'calls_need',
      params: { accountId: 1 },
      query: { call: 1 },
    });
  });

  it('mutes the call on the notification’s 略過', async () => {
    PathorsCallsAPI.dismiss.mockResolvedValue({ dismissed: true });
    await mountNotifier([
      activeCall(1, { interruptions: 4 }),
      activeCall(2, {}, { needs_action: true }),
    ]);
    const store = usePathorsLiveCallsStore();

    await fromWorker({ type: 'pathors-call:dismiss', callId: 1 });
    await fromWorker({ type: 'pathors-call:dismiss', callId: 2 });

    expect(store.records.find(call => call.id === 1).warningMuted).toBe(true);
    expect(PathorsCallsAPI.dismiss).toHaveBeenCalledWith(2);
    expect(store.attentionCallsAt(NOW)).toEqual([]);
  });

  it('flashes the tab title while the dashboard is behind', async () => {
    // Timers too this time, not just the clock.
    vi.useRealTimers();
    vi.useFakeTimers({ now: NOW });
    globalThis.document.title = 'Pathors Inbox';
    await mountNotifier([activeCall(1, { interruptions: 4 })]);

    vi.advanceTimersByTime(1000);
    expect(globalThis.document.title).toBe('● 客人1：被打斷 4 次');
    vi.advanceTimersByTime(1000);
    expect(globalThis.document.title).toBe('Pathors Inbox');

    vi.advanceTimersByTime(1000);
    focused = true;
    globalThis.dispatchEvent(new Event('focus'));
    await nextTick();
    expect(globalThis.document.title).toBe('Pathors Inbox');
  });
});
