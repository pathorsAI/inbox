import { flushPromises, mount, RouterLinkStub } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import CrmSyncStatus from '../CrmSyncStatus.vue';

const { getEvents, getBackfill, startBackfill } = vi.hoisted(() => ({
  getEvents: vi.fn(),
  getBackfill: vi.fn(),
  startBackfill: vi.fn(),
}));

vi.mock('dashboard/api/integrations/crmSync', () => ({
  default: { getEvents, getBackfill, startBackfill },
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '7' } }),
}));

const KEY = 'INTEGRATION_SETTINGS.CRM_SYNC';

const summary = {
  last_success_at: '2026-09-30T10:42:00Z',
  last_24h: { success: 126, failure: 2, rate_limited: 3 },
  pending_conflicts: 4,
};

const linkedEvent = {
  id: 3,
  action: 'linked',
  status: 'success',
  message: null,
  details: {},
  contact: { id: 174, name: 'Rea Sagang' },
  created_at: '2026-09-30T10:42:00Z',
};

const failedEvent = {
  id: 2,
  action: 'failed',
  status: 'failure',
  message: 'Twenty returned 500: upstream timeout while writing the person',
  details: { error_class: 'Crm::Twenty::Api::Client::ApiError' },
  contact: { id: 9, name: 'Anna Tsai' },
  created_at: '2026-09-30T10:40:00Z',
};

const filledEvent = {
  id: 1,
  action: 'filled_fields',
  status: 'success',
  message: null,
  details: { fields: ['company_name', 'email'] },
  contact: null,
  created_at: '2026-09-30T10:30:00Z',
};

const eventsPage = (events, { page = 1, hasMore = false } = {}) => ({
  data: { summary, events, meta: { page, has_more: hasMore } },
});

const backfillStatus = (state, extra = {}) => ({
  data: {
    state,
    total: 280,
    processed: 0,
    linked: 0,
    refreshed: 0,
    ambiguous: 0,
    no_match: 0,
    errors: 0,
    started_at: null,
    finished_at: null,
    ...extra,
  },
});

const mountStatus = async (props = {}) => {
  const wrapper = mount(CrmSyncStatus, {
    props: { hookId: 11, conflictsAnchor: 'crm-conflicts', ...props },
    global: { stubs: { RouterLink: RouterLinkStub } },
  });
  await flushPromises();
  return wrapper;
};

const buttonLabelled = (wrapper, key) =>
  wrapper.findAll('button').find(button => button.text() === `${KEY}.${key}`);

describe('CrmSyncStatus', () => {
  beforeEach(() => {
    vi.useFakeTimers({ now: new Date('2026-09-30T10:45:00Z') });
    getEvents.mockResolvedValue(
      eventsPage([linkedEvent, failedEvent, filledEvent])
    );
    getBackfill.mockResolvedValue(backfillStatus('idle'));
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('renders the summary and the events of the hook', async () => {
    const wrapper = await mountStatus();

    expect(getEvents).toHaveBeenCalledWith(11, {
      page: 1,
      status: undefined,
    });
    expect(getBackfill).toHaveBeenCalledWith(11);

    const text = wrapper.text();
    expect(text).toContain(`${KEY}.LAST_SUCCESS`);
    ['126', '2', '3', '4'].forEach(value => expect(text).toContain(value));
    expect(text).toContain(`${KEY}.STATS.PENDING_CONFLICTS`);

    const rows = wrapper.findAll('li');
    expect(rows).toHaveLength(3);
    expect(rows[0].text()).toContain('10:42');
    expect(rows[0].text()).toContain(`${KEY}.ACTIONS.LINKED`);
    expect(rows[0].text()).toContain(`${KEY}.STATUS.SUCCESS`);
    expect(rows[0].findComponent(RouterLinkStub).props('to')).toEqual({
      name: 'contacts_edit',
      params: { accountId: '7', contactId: 174 },
    });

    expect(rows[1].text()).toContain(`${KEY}.ACTIONS.FAILED`);
    expect(rows[1].text()).toContain(failedEvent.message);
    expect(rows[1].text()).toContain(`${KEY}.STATUS.FAILURE`);

    expect(rows[2].text()).toContain(`${KEY}.ACTIONS.FILLED_FIELDS`);
    expect(rows[2].findComponent(RouterLinkStub).exists()).toBe(false);
  });

  it('shows the never-synced state', async () => {
    getEvents.mockResolvedValue({
      data: {
        summary: { ...summary, last_success_at: null },
        events: [],
        meta: { page: 1, has_more: false },
      },
    });
    const wrapper = await mountStatus();

    expect(wrapper.text()).toContain(`${KEY}.NEVER_SYNCED`);
    expect(wrapper.text()).toContain(`${KEY}.EVENTS.EMPTY`);
  });

  it('scrolls to the conflicts section from the pending count', async () => {
    const section = document.createElement('section');
    section.id = 'crm-conflicts';
    section.scrollIntoView = vi.fn();
    document.body.appendChild(section);
    const wrapper = await mountStatus();

    await wrapper
      .findAll('button')
      .find(button => button.text() === '4')
      .trigger('click');

    expect(section.scrollIntoView).toHaveBeenCalled();
    section.remove();
  });

  it('refetches only failures when the filter is on', async () => {
    const wrapper = await mountStatus();
    getEvents.mockResolvedValue(eventsPage([failedEvent]));

    await wrapper.find('input[type="checkbox"]').setValue(true);
    await flushPromises();

    expect(getEvents).toHaveBeenLastCalledWith(11, {
      page: 1,
      status: 'failure',
    });
    expect(wrapper.findAll('li')).toHaveLength(1);
  });

  it('appends the next page on load more', async () => {
    getEvents.mockResolvedValueOnce(
      eventsPage([linkedEvent, failedEvent], { hasMore: true })
    );
    const wrapper = await mountStatus();
    getEvents.mockResolvedValueOnce(eventsPage([filledEvent], { page: 2 }));

    await buttonLabelled(wrapper, 'EVENTS.LOAD_MORE').trigger('click');
    await flushPromises();

    expect(getEvents).toHaveBeenLastCalledWith(11, {
      page: 2,
      status: undefined,
    });
    expect(wrapper.findAll('li')).toHaveLength(3);
    expect(buttonLabelled(wrapper, 'EVENTS.LOAD_MORE')).toBeUndefined();
  });

  it('confirms, starts the backfill and polls until it finishes', async () => {
    const wrapper = await mountStatus();
    startBackfill.mockResolvedValue(backfillStatus('running'));
    getBackfill
      .mockResolvedValueOnce(backfillStatus('running', { processed: 70 }))
      .mockResolvedValueOnce(backfillStatus('running', { processed: 140 }))
      .mockResolvedValueOnce(
        backfillStatus('finished', {
          processed: 280,
          linked: 14,
          finished_at: '2026-09-30T10:44:00Z',
        })
      );

    await buttonLabelled(wrapper, 'BACKFILL.BUTTON').trigger('click');
    expect(startBackfill).not.toHaveBeenCalled();
    await buttonLabelled(wrapper, 'BACKFILL.START').trigger('click');
    await flushPromises();

    expect(startBackfill).toHaveBeenCalledWith(11);
    expect(wrapper.text()).toContain(`${KEY}.BACKFILL.RUNNING`);
    expect(
      wrapper.find('[data-test="backfill-progress"]').attributes('style')
    ).toContain('width: 25%');

    await vi.advanceTimersByTimeAsync(3000);
    expect(
      wrapper.find('[data-test="backfill-progress"]').attributes('style')
    ).toContain('width: 50%');

    const eventCalls = getEvents.mock.calls.length;
    await vi.advanceTimersByTimeAsync(3000);
    expect(wrapper.find('[data-test="backfill-progress"]').exists()).toBe(
      false
    );
    expect(wrapper.text()).toContain(`${KEY}.BACKFILL.FINISHED`);
    expect(wrapper.text()).toContain(`${KEY}.BACKFILL.COUNTS`);
    expect(getEvents.mock.calls.length).toBe(eventCalls + 1);

    await vi.advanceTimersByTimeAsync(9000);
    // One load on mount, then three polls.
    expect(getBackfill).toHaveBeenCalledTimes(4);
  });

  it('follows a run that is already going on a 409', async () => {
    const wrapper = await mountStatus();
    startBackfill.mockRejectedValue({
      response: { status: 409, data: { error: 'already_running' } },
    });
    getBackfill.mockResolvedValue(backfillStatus('running', { processed: 28 }));

    await buttonLabelled(wrapper, 'BACKFILL.BUTTON').trigger('click');
    await buttonLabelled(wrapper, 'BACKFILL.START').trigger('click');
    await flushPromises();

    expect(useAlert).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain(`${KEY}.BACKFILL.ALREADY_RUNNING`);
    expect(
      wrapper.find('[data-test="backfill-progress"]').attributes('style')
    ).toContain('width: 10%');

    await vi.advanceTimersByTimeAsync(3000);
    expect(getBackfill).toHaveBeenCalledTimes(3);
  });

  it('shows progress of an earlier run and stops polling on unmount', async () => {
    getBackfill.mockResolvedValue(backfillStatus('running', { processed: 56 }));
    const wrapper = await mountStatus();

    expect(wrapper.text()).toContain(`${KEY}.BACKFILL.RUNNING`);
    await vi.advanceTimersByTimeAsync(3000);
    expect(getBackfill).toHaveBeenCalledTimes(2);

    wrapper.unmount();
    await vi.advanceTimersByTimeAsync(9000);
    expect(getBackfill).toHaveBeenCalledTimes(2);
  });
});
