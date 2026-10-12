import { setActivePinia, createPinia } from 'pinia';
import CallsAPI from 'dashboard/api/calls';
import {
  CALL_COUNTS_REFRESH_DELAY_MS,
  resetCallCountsRefresh,
  useCallCountsStore,
} from '../callCounts';

vi.mock('dashboard/api/calls', () => ({ default: { get: vi.fn() } }));

const respond = counts =>
  CallsAPI.get.mockResolvedValue({ data: { meta: { counts }, payload: [] } });

describe('callCounts store', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    resetCallCountsRefresh();
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('reads the badges from the cheapest list request', async () => {
    respond({ need: 3, live: 5 });
    const store = useCallCountsStore();

    await store.fetch();

    expect(CallsAPI.get).toHaveBeenCalledWith({ segment: 'need', page: 1 });
    expect(store.counts).toEqual({ need: 3, live: 5 });
  });

  it('keeps the last counts when a fetch fails', async () => {
    respond({ need: 2, live: 1 });
    const store = useCallCountsStore();
    await store.fetch();
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    CallsAPI.get.mockRejectedValue(new Error('offline'));

    await store.fetch();

    expect(store.counts).toEqual({ need: 2, live: 1 });
  });

  it('collapses a burst of refresh requests into one fetch', async () => {
    respond({ need: 1, live: 1 });
    const store = useCallCountsStore();

    store.scheduleFetch();
    store.scheduleFetch();
    vi.advanceTimersByTime(CALL_COUNTS_REFRESH_DELAY_MS - 1);
    store.scheduleFetch();
    vi.advanceTimersByTime(CALL_COUNTS_REFRESH_DELAY_MS);
    await vi.runAllTimersAsync();

    expect(CallsAPI.get).toHaveBeenCalledTimes(1);
    expect(store.counts).toEqual({ need: 1, live: 1 });
  });
});
