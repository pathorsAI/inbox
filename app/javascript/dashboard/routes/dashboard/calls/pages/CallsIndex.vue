<script setup>
import { computed, ref, watch, onMounted } from 'vue';
import { until } from '@vueuse/core';
import { debounce } from '@chatwoot/utils';
import camelcaseKeys from 'camelcase-keys';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useClock } from 'dashboard/composables/useClock';
import { isCallLineInbox } from 'dashboard/helper/inbox';
import CallsAPI from 'dashboard/api/calls';
import {
  CALL_OUTCOMES,
  primaryCallState,
} from 'dashboard/helper/pathorsCallState';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { useCallHistoryStore } from 'dashboard/stores/callHistory';
import { useCallCountsStore } from 'dashboard/stores/callCounts';
import { usePathorsLiveCallsStore } from 'dashboard/stores/pathorsLiveCalls';

import CallDetailSheet from 'dashboard/components-next/Calls/CallDetailSheet.vue';
import CallsEmptyState from 'dashboard/components-next/Calls/CallsEmptyState.vue';
import CallsFilterBar from 'dashboard/components-next/Calls/CallsFilterBar.vue';
import CallsTable from 'dashboard/components-next/Calls/CallsTable.vue';
import {
  CALL_DATE_RANGES,
  CALL_SECTIONS,
  CALL_SEGMENTS,
  CALL_VIEWS,
  CALLS_PER_PAGE,
  CALLS_REFRESH_DELAY_MS,
  CALLS_SEARCH_DEBOUNCE_MS,
  VIEW_SEGMENT,
  callSection,
  dateRangeParams,
  mergeLiveCall,
} from 'dashboard/components-next/Calls/constants';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  // One of CALL_VIEWS; each sidebar entry is its own route.
  view: { type: String, required: true },
  // The line of the `line` view.
  inboxId: { type: Number, default: null },
});

const OUTCOME_FILTERS = [...CALL_OUTCOMES, 'takeover_requested'];
const SEGMENT_VALUES = Object.values(CALL_SEGMENTS);
const VIEW_TITLE_KEYS = {
  [CALL_VIEWS.NEED]: 'CALLS_PAGE.VIEWS.NEED',
  [CALL_VIEWS.LIVE]: 'CALLS_PAGE.VIEWS.LIVE',
  [CALL_VIEWS.ALL]: 'CALLS_PAGE.VIEWS.ALL',
  [CALL_VIEWS.MINE]: 'CALLS_PAGE.VIEWS.MINE',
};

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();
const callHistoryStore = useCallHistoryStore();
const callCountsStore = useCallCountsStore();
const liveCallsStore = usePathorsLiveCallsStore();
const now = useClock();

const inboxes = useMapGetter('inboxes/getInboxes');
const accountId = useMapGetter('getCurrentAccountId');
const currentUserId = useMapGetter('getCurrentUserID');
const accountUiFlags = useMapGetter('accounts/getUIFlags');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);

const lineInboxes = computed(() => inboxes.value.filter(isCallLineInbox));
const hasCallLines = computed(
  () =>
    isFeatureEnabledonAccount.value(
      accountId.value,
      FEATURE_FLAGS.CHANNEL_VOICE
    ) && lineInboxes.value.length > 0
);

const isLineView = computed(() => props.view === CALL_VIEWS.LINE);
const fixedSegment = computed(() => VIEW_SEGMENT[props.view] || null);

// --- Filters: the URL query is the source of truth ------------------------------

const pick = (value, allowed) => (allowed.includes(value) ? value : null);

const filters = computed(() => ({
  q: typeof route.query.q === 'string' ? route.query.q : '',
  segment: fixedSegment.value || pick(route.query.segment, SEGMENT_VALUES),
  date: pick(route.query.date, CALL_DATE_RANGES),
  outcome: pick(route.query.outcome, OUTCOME_FILTERS),
  inboxId: isLineView.value
    ? props.inboxId
    : Number(route.query.inbox_id) || null,
  page: Number(route.query.page) || 1,
}));

const openCallId = computed(() => Number(route.query.call) || null);

const isBlank = value => value === null || value === undefined || value === '';

// Any filter change starts over from page 1; opening a call does not.
const updateQuery = (patch, { resetPage = true } = {}) => {
  const next = { ...route.query, ...(resetPage && { page: null }), ...patch };
  router.replace({
    query: Object.fromEntries(
      Object.entries(next).filter(([, value]) => !isBlank(value))
    ),
  });
};

const filterModel = (filterKey, queryKey = filterKey) =>
  computed({
    get: () => filters.value[filterKey],
    set: value => updateQuery({ [queryKey]: value }),
  });

const segmentModel = filterModel('segment');
const dateModel = filterModel('date');
const outcomeModel = filterModel('outcome');
const inboxModel = filterModel('inboxId', 'inbox_id');

const searchTerm = ref(filters.value.q);
const pushSearch = debounce(
  value => updateQuery({ q: value.trim() }),
  CALLS_SEARCH_DEBOUNCE_MS
);
watch(searchTerm, value => {
  if (value.trim() !== filters.value.q) pushSearch(value);
});
watch(
  () => filters.value.q,
  q => {
    if (q !== searchTerm.value.trim()) searchTerm.value = q;
  }
);

const hasFilters = computed(
  () => !!(filters.value.q || filters.value.date || filters.value.outcome)
);

// --- Data ------------------------------------------------------------------------

const calls = computed(() => callHistoryStore.records);
const meta = computed(() => callHistoryStore.meta);
const isFetching = computed(() => callHistoryStore.uiFlags.isFetching);
const isInitializing = ref(true);

const fetchParams = computed(() => {
  const { page, segment, q, date, outcome, inboxId } = filters.value;
  return {
    page,
    ...(segment && { segment }),
    ...(q && { q }),
    ...dateRangeParams(date),
    ...(outcome && { outcome }),
    ...(inboxId && { inbox_id: inboxId }),
    ...(props.view === CALL_VIEWS.MINE && { mine: true }),
  };
});

const fetchCalls = async () => {
  try {
    await callHistoryStore.fetchCalls(fetchParams.value);
    // Unscoped by line, the counts are the sidebar's badges too.
    if (!filters.value.inboxId && meta.value.counts) {
      callCountsStore.$patch({ counts: meta.value.counts });
    }
  } catch (error) {
    useAlert(error.message);
  }
};

watch(
  () => JSON.stringify(fetchParams.value),
  () => {
    if (!isInitializing.value && hasCallLines.value) fetchCalls();
  }
);

// Calls move between sections as the AI asks for help, someone answers or the
// call ends; the live store hears about it first.
const scheduleRefresh = debounce(fetchCalls, CALLS_REFRESH_DELAY_MS);
watch(
  () => liveCallsStore.handlingSignature,
  () => {
    if (!isInitializing.value && hasCallLines.value) scheduleRefresh();
  }
);

const liveRecordsById = computed(
  () => new Map(liveCallsStore.records.map(record => [record.id, record]))
);

const rows = computed(() =>
  calls.value.map(row => {
    const call = mergeLiveCall(
      row,
      liveRecordsById.value.get(row.id),
      liveCallsStore.liveById[row.id]
    );
    const state = primaryCallState(call, {
      now: now.value,
      currentUserId: currentUserId.value,
    });
    return { call, state, section: callSection(call, state) };
  })
);

const sections = computed(() =>
  CALL_SECTIONS.map(key => ({
    key,
    rows: rows.value.filter(row => row.section === key),
  })).filter(section => section.rows.length)
);

// --- Header --------------------------------------------------------------------

const title = computed(() => {
  if (isLineView.value) {
    return (
      inboxes.value.find(inbox => inbox.id === props.inboxId)?.name ||
      t('CALLS_PAGE.HEADER')
    );
  }
  return t(VIEW_TITLE_KEYS[props.view] || 'CALLS_PAGE.HEADER');
});

const liveCount = computed(() => meta.value.counts?.live || 0);

const emptyState = computed(() => {
  if (hasFilters.value) return { title: t('CALLS_PAGE.EMPTY.FILTERED') };
  if (props.view === CALL_VIEWS.NEED) {
    return {
      title: t('CALLS_PAGE.EMPTY.NEED'),
      hint: t('CALLS_PAGE.EMPTY.NEED_HINT'),
    };
  }
  if (props.view === CALL_VIEWS.LIVE)
    return { title: t('CALLS_PAGE.EMPTY.LIVE') };
  return { title: t('CALLS_PAGE.EMPTY_STATE') };
});

// --- Sheet ---------------------------------------------------------------------

// A call opened by id that is neither on this page nor live (a link from its
// conversation to an ended call on a later page) is fetched on its own.
const fetchedCall = ref(null);

const selectedCall = computed(() => {
  if (!openCallId.value) return null;
  const row = rows.value.find(item => item.call.id === openCallId.value);
  if (row) return row.call;
  // Not on this page (an alert for a call the list has not caught up with).
  const record = liveRecordsById.value.get(openCallId.value);
  if (record) {
    return { ...record, live: liveCallsStore.liveById[record.id] || null };
  }
  return fetchedCall.value?.id === openCallId.value ? fetchedCall.value : null;
});

const fetchOpenCall = async callId => {
  try {
    const { data } = await CallsAPI.show(callId);
    // `variables` are the AI's own extraction keys; keep them verbatim.
    if (openCallId.value === callId) {
      fetchedCall.value = camelcaseKeys(data, {
        deep: true,
        stopPaths: ['variables'],
      });
    }
  } catch {
    if (openCallId.value === callId) useAlert(t('CALLS_PAGE.SHEET.NOT_FOUND'));
  }
};

watch(
  [openCallId, isFetching],
  ([callId, fetching]) => {
    if (!callId || fetching || selectedCall.value) return;
    fetchOpenCall(callId);
  },
  { immediate: true }
);

const openCall = call => updateQuery({ call: call.id }, { resetPage: false });
const closeSheet = () => updateQuery({ call: null }, { resetPage: false });

const patchRow = (callId, changes) => {
  const record = callHistoryStore.records.find(item => item.id === callId);
  if (record) Object.assign(record, changes);
};

const onDismissed = callId => patchRow(callId, { dismissed: true });

const onFollowUpResolved = callId => {
  patchRow(callId, { followUp: false });
  scheduleRefresh();
  callCountsStore.scheduleFetch();
};

const onPageChange = page => updateQuery({ page }, { resetPage: false });

onMounted(async () => {
  try {
    await Promise.all([
      store.dispatch('inboxes/get'),
      until(() => accountUiFlags.value.isFetchingItem).toBe(false),
    ]);
    if (!hasCallLines.value) return;
    liveCallsStore.ensureLoaded();
    await fetchCalls();
  } finally {
    isInitializing.value = false;
  }
});
</script>

<template>
  <div
    v-if="isInitializing"
    class="flex items-center justify-center w-full h-full bg-n-surface-1"
  >
    <Spinner :size="24" />
  </div>
  <CallsEmptyState v-else-if="!hasCallLines" />
  <section
    v-else
    class="relative flex flex-col w-full h-full overflow-hidden bg-n-surface-1"
  >
    <header class="shrink-0">
      <div class="flex items-center gap-3 w-full px-6 pt-6">
        <h1 class="text-xl font-medium truncate text-n-slate-12">
          {{ title }}
        </h1>
        <span
          v-if="liveCount"
          class="inline-flex items-center gap-1.5 px-2 rounded-md text-xs font-medium leading-6 bg-n-teal-3 text-n-teal-11 shrink-0"
          data-test-id="calls-live-count"
        >
          <span
            class="rounded-full size-1.5 bg-current motion-safe:animate-pulse"
          />
          {{ t('CALLS_PAGE.LIVE_COUNT', { count: liveCount }) }}
        </span>
      </div>
      <CallsFilterBar
        v-model:search="searchTerm"
        v-model:segment="segmentModel"
        v-model:date-range="dateModel"
        v-model:outcome="outcomeModel"
        v-model:inbox-id="inboxModel"
        class="pb-4 mx-6 mt-5 border-b border-n-weak"
        :show-segments="!fixedSegment"
        :counts="meta.counts || {}"
        :inboxes="isLineView ? [] : lineInboxes"
      />
    </header>
    <main class="flex-1 min-w-0 px-6 overflow-y-auto">
      <div
        v-if="isFetching && !calls.length"
        class="flex items-center justify-center py-16"
      >
        <Spinner :size="24" />
      </div>
      <div
        v-else-if="!calls.length"
        class="flex flex-col items-center gap-1 py-20 text-center"
        data-test-id="calls-empty"
      >
        <span class="text-base text-n-slate-11">{{ emptyState.title }}</span>
        <span v-if="emptyState.hint" class="text-sm text-n-slate-10">
          {{ emptyState.hint }}
        </span>
      </div>
      <CallsTable
        v-else
        :sections="sections"
        :selected-id="openCallId"
        :now="now"
        :class="{ 'opacity-60': isFetching }"
        @open="openCall"
      />
    </main>
    <footer v-if="calls.length" class="sticky bottom-0 shrink-0">
      <PaginationFooter
        :current-page="filters.page"
        :total-items="meta.count"
        :items-per-page="CALLS_PER_PAGE"
        @update:current-page="onPageChange"
      />
    </footer>
    <CallDetailSheet
      v-if="selectedCall"
      :call="selectedCall"
      :account-id="accountId"
      :current-user-id="currentUserId"
      @close="closeSheet"
      @dismissed="onDismissed"
      @follow-up-resolved="onFollowUpResolved"
    />
  </section>
</template>
