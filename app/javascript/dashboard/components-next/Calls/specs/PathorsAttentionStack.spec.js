import { flushPromises, mount } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import { withFullI18n } from 'test-i18n';
import PathorsCallsAPI from 'dashboard/api/pathorsCalls';
import {
  usePathorsLiveCallsStore,
  resetPathorsLiveCallsTracking,
} from 'dashboard/stores/pathorsLiveCalls';
import { useAlert } from 'dashboard/composables';
import PathorsAttentionStack from '../PathorsAttentionStack.vue';

withFullI18n('zh_TW');

const { push, featureEnabled } = vi.hoisted(() => ({
  push: vi.fn(),
  featureEnabled: { value: true },
}));

const currentRoute = { name: 'inbox_dashboard' };
vi.mock('vue-router', () => ({
  useRoute: () => currentRoute,
  useRouter: () => ({ push }),
}));

vi.mock('dashboard/api/pathorsCalls', () => ({
  default: { active: vi.fn(), dismiss: vi.fn() },
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  const getters = {
    getCurrentAccountId: () => 1,
    'inboxes/getInbox': () => id => ({ id, name: `線路${id}` }),
    'accounts/isFeatureEnabledonAccount': () => () => featureEnabled.value,
  };
  return { useMapGetter: key => computed(getters[key]) };
});

const NOW = Date.parse('2026-10-11T10:00:00Z');

const activeCall = (id, live, overrides = {}) => ({
  id,
  provider: 'pathors',
  status: 'in-progress',
  conversation_id: 100 + id,
  inbox_name: '總機',
  contact_name: `客人${id}`,
  started_at: '2026-10-11T09:50:00Z',
  needs_action: true,
  dismissed: false,
  live: { seq: 1, turns: 3, interruptions: 0, transcript: [], ...live },
  ...overrides,
});

const requested = (at = NOW - 3 * 60_000) => ({
  attention: {
    takeover_request: {
      reason: 'cannot_hear',
      detail: '收訊很差',
      source: 'ai',
      at,
    },
  },
});

const failed = at => ({
  attention: {
    transfer: {
      phase: 'failed',
      target_masked: '****5678',
      failure_reason: 'busy',
      at,
    },
  },
});

const mountStack = async payload => {
  PathorsCallsAPI.active.mockResolvedValue({ payload });
  // jsdom never ends a CSS transition, so a leaving card would stay put.
  const wrapper = mount(PathorsAttentionStack, {
    global: { stubs: { 'transition-group': true } },
  });
  await flushPromises();
  return wrapper;
};

const cards = wrapper =>
  wrapper.findAll('[data-test-id="pathors-attention-card"]');

describe('PathorsAttentionStack', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    resetPathorsLiveCallsTracking();
    featureEnabled.value = true;
    currentRoute.name = 'inbox_dashboard';
    vi.useFakeTimers({ now: NOW, toFake: ['Date'] });
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('seeds the live store itself and shows a card per call needing a human', async () => {
    const wrapper = await mountStack([
      activeCall(1, requested()),
      activeCall(2, failed(NOW - 60_000)),
      activeCall(3, {}, { needs_action: false }),
    ]);

    expect(PathorsCallsAPI.active).toHaveBeenCalledTimes(1);
    const shown = cards(wrapper);
    expect(shown.map(card => card.attributes('data-call-id'))).toEqual([
      '2',
      '1',
    ]);
    expect(shown[0].text()).toContain('轉接失敗');
    expect(shown[0].text()).toContain('客人2 · 總機');
    expect(shown[0].text()).toContain('****5678');
    expect(shown[1].text()).toContain('AI 請求支援');
    expect(shown[1].text()).toContain('3 分鐘前');
    expect(shown[1].text()).toContain('聽不清楚客人 · 收訊很差');
  });

  it('falls back to the inbox list for a call first seen through its message', async () => {
    const wrapper = await mountStack([
      activeCall(1, requested(), { inbox_name: null, inbox_id: 4 }),
    ]);

    expect(cards(wrapper)[0].text()).toContain('客人1 · 線路4');
  });

  it('shows at most three cards and counts the rest', async () => {
    const wrapper = await mountStack(
      [1, 2, 3, 4, 5].map(id => activeCall(id, requested(NOW - id * 1000)))
    );

    expect(cards(wrapper)).toHaveLength(3);
    expect(wrapper.find('[data-test-id="pathors-attention-more"]').text()).toBe(
      '還有 2 通'
    );
  });

  it('mutes a call for this agent on 略過', async () => {
    PathorsCallsAPI.dismiss.mockResolvedValue({ dismissed: true });
    const wrapper = await mountStack([activeCall(1, requested())]);

    await wrapper
      .find('[data-test-id="pathors-attention-dismiss"]')
      .trigger('click');
    await flushPromises();

    expect(PathorsCallsAPI.dismiss).toHaveBeenCalledWith(1);
    expect(cards(wrapper)).toHaveLength(0);
  });

  it('brings the card back and says so when 略過 fails', async () => {
    PathorsCallsAPI.dismiss.mockRejectedValue(new Error('offline'));
    const wrapper = await mountStack([activeCall(1, requested())]);

    await wrapper
      .find('[data-test-id="pathors-attention-dismiss"]')
      .trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('無法略過這通通話');
    expect(cards(wrapper)).toHaveLength(1);
  });

  it('opens the call on the calls page without joining it', async () => {
    const wrapper = await mountStack([activeCall(1, requested())]);

    await wrapper
      .find('[data-test-id="pathors-attention-go"]')
      .trigger('click');

    expect(push).toHaveBeenCalledWith({
      name: 'calls_need',
      params: { accountId: 1 },
      query: { call: 1 },
    });
  });

  it('leaves out the call open in the sheet', async () => {
    const wrapper = await mountStack([
      activeCall(1, requested()),
      activeCall(2, requested(NOW - 1000)),
    ]);

    usePathorsLiveCallsStore().setOpenCallId(2);
    await flushPromises();

    expect(cards(wrapper).map(card => card.attributes('data-call-id'))).toEqual(
      ['1']
    );
  });

  it('stays out of the way on the calls pages, which list these calls already', async () => {
    currentRoute.name = 'calls_need';
    const wrapper = await mountStack([activeCall(1, requested())]);

    expect(cards(wrapper)).toHaveLength(0);
  });

  it('does nothing without voice calls on the account', async () => {
    featureEnabled.value = false;
    const wrapper = await mountStack([activeCall(1, requested())]);

    expect(PathorsCallsAPI.active).not.toHaveBeenCalled();
    expect(cards(wrapper)).toHaveLength(0);
  });
});
