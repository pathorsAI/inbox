import { defineStore } from 'pinia';
import CallsAPI from 'dashboard/api/calls';

// Bursts of live updates (every AI turn on every call) collapse into one fetch.
export const CALL_COUNTS_REFRESH_DELAY_MS = 1000;

let refreshTimer = null;

/**
 * The sidebar badges for the 通話 group: calls that need a human and calls on
 * the line. CallFinder counts both alongside any list request, ignoring the
 * segment, so the cheapest request (page 1 of `need`) carries them.
 */
export const useCallCountsStore = defineStore('callCounts', {
  state: () => ({
    counts: { need: 0, live: 0 },
  }),

  actions: {
    async fetch() {
      try {
        const { data } = await CallsAPI.get({ segment: 'need', page: 1 });
        this.counts = { need: 0, live: 0, ...data.meta?.counts };
      } catch (error) {
        // A stale badge until the next poll beats a toast on every page.
        // eslint-disable-next-line no-console
        console.warn('[call-counts] could not load call counts', error);
      }
    },

    scheduleFetch() {
      clearTimeout(refreshTimer);
      refreshTimer = setTimeout(() => {
        refreshTimer = null;
        this.fetch();
      }, CALL_COUNTS_REFRESH_DELAY_MS);
    },
  },
});

// Test seam: a pending timer would otherwise fire into the next spec.
export const resetCallCountsRefresh = () => {
  clearTimeout(refreshTimer);
  refreshTimer = null;
};
