<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useTimeoutPoll } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { format, isToday } from 'date-fns';
import { useAlert } from 'dashboard/composables';
import { generateRelativeTime } from 'shared/helpers/DateHelper';
import CrmSyncAPI from 'dashboard/api/integrations/crmSync';
import Button from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  hookId: { type: Number, required: true },
  // Element id of this CRM's conflicts section on the page, if it has one.
  conflictsAnchor: { type: String, default: '' },
});

const POLL_INTERVAL = 3000;
const NOTE_ACTIONS = new Set([
  'note_synced',
  'note_deleted',
  'conversation_logged',
]);
const CHIP_CLASSES = {
  SUCCESS: 'bg-n-teal-3 text-n-teal-11',
  FAILURE: 'bg-n-ruby-3 text-n-ruby-11',
  CONFLICT: 'bg-n-amber-3 text-n-amber-11',
  NOTE: 'bg-n-iris-3 text-n-iris-11',
  RATE_LIMITED: 'bg-n-slate-3 text-n-slate-11',
};
const RELATIVE_UNITS = [
  ['day', 86400],
  ['hour', 3600],
  ['minute', 60],
];

const { t, locale } = useI18n();
const route = useRoute();

const summary = ref(null);
const events = ref([]);
const page = ref(1);
const hasMore = ref(false);
const onlyFailures = ref(false);
const isLoadingEvents = ref(false);
const eventsError = ref('');

const backfill = ref(null);
const isConfirming = ref(false);
const isStarting = ref(false);
const alreadyRunning = ref(false);

const relativeTime = iso => {
  const seconds = (new Date(iso) - Date.now()) / 1000;
  const [unit, size] = RELATIVE_UNITS.find(
    ([, unitSeconds]) => Math.abs(seconds) >= unitSeconds
  ) || ['second', 1];
  return generateRelativeTime(Math.round(seconds / size), unit, locale.value);
};

const clockTime = iso => {
  const date = new Date(iso);
  return format(date, isToday(date) ? 'HH:mm' : 'M/d HH:mm');
};

const lastSuccess = computed(() =>
  summary.value.last_success_at
    ? t('INTEGRATION_SETTINGS.CRM_SYNC.LAST_SUCCESS', {
        time: relativeTime(summary.value.last_success_at),
      })
    : t('INTEGRATION_SETTINGS.CRM_SYNC.NEVER_SYNCED')
);

const stats = computed(() => {
  const { last_24h: last24h, pending_conflicts: pendingConflicts } =
    summary.value;
  return [
    {
      key: 'synced',
      label: t('INTEGRATION_SETTINGS.CRM_SYNC.STATS.SYNCED_24H'),
      value: last24h.success,
    },
    {
      key: 'failure',
      label: t('INTEGRATION_SETTINGS.CRM_SYNC.STATS.FAILURE'),
      value: last24h.failure,
      alert: last24h.failure > 0,
    },
    {
      key: 'rate_limited',
      label: t('INTEGRATION_SETTINGS.CRM_SYNC.STATS.RATE_LIMITED'),
      value: last24h.rate_limited,
    },
    {
      key: 'conflicts',
      label: t('INTEGRATION_SETTINGS.CRM_SYNC.STATS.PENDING_CONFLICTS'),
      value: pendingConflicts,
      anchor: pendingConflicts > 0 && props.conflictsAnchor,
    },
  ];
});

const scrollTo = id =>
  document.getElementById(id).scrollIntoView({ behavior: 'smooth' });

const contactRoute = contactId => ({
  name: 'contacts_edit',
  params: { accountId: route.params.accountId, contactId },
});

const fieldLabels = computed(() => ({
  name: t('INTEGRATION_SETTINGS.CRM_SYNC.FIELDS.NAME'),
  email: t('INTEGRATION_SETTINGS.CRM_SYNC.FIELDS.EMAIL'),
  phone: t('INTEGRATION_SETTINGS.CRM_SYNC.FIELDS.PHONE'),
  phone_number: t('INTEGRATION_SETTINGS.CRM_SYNC.FIELDS.PHONE'),
  company: t('INTEGRATION_SETTINGS.CRM_SYNC.FIELDS.COMPANY'),
  company_name: t('INTEGRATION_SETTINGS.CRM_SYNC.FIELDS.COMPANY'),
  city: t('INTEGRATION_SETTINGS.CRM_SYNC.FIELDS.CITY'),
  linkedin: t('INTEGRATION_SETTINGS.CRM_SYNC.FIELDS.LINKEDIN'),
  job_title: t('INTEGRATION_SETTINGS.CRM_SYNC.FIELDS.JOB_TITLE'),
}));

// Fields outside the map show their raw key rather than nothing.
const fieldLabel = field => fieldLabels.value[field] || field;

const CONFLICT_SENTENCES = {
  field: ({ field }) =>
    t('INTEGRATION_SETTINGS.CRM_SYNC.ACTIONS.CONFLICT_RAISED.FIELD', {
      field: fieldLabel(field),
    }),
  ambiguous: () =>
    t('INTEGRATION_SETTINGS.CRM_SYNC.ACTIONS.CONFLICT_RAISED.AMBIGUOUS'),
  duplicate_contact: () =>
    t(
      'INTEGRATION_SETTINGS.CRM_SYNC.ACTIONS.CONFLICT_RAISED.DUPLICATE_CONTACT'
    ),
};

const SENTENCES = {
  linked: () => t('INTEGRATION_SETTINGS.CRM_SYNC.ACTIONS.LINKED'),
  created_person: () =>
    t('INTEGRATION_SETTINGS.CRM_SYNC.ACTIONS.CREATED_PERSON'),
  filled_fields: ({ fields }) =>
    t('INTEGRATION_SETTINGS.CRM_SYNC.ACTIONS.FILLED_FIELDS', {
      fields: fields
        .map(fieldLabel)
        .join(t('INTEGRATION_SETTINGS.CRM_SYNC.LIST_SEPARATOR')),
    }),
  note_synced: () => t('INTEGRATION_SETTINGS.CRM_SYNC.ACTIONS.NOTE_SYNCED'),
  note_deleted: () => t('INTEGRATION_SETTINGS.CRM_SYNC.ACTIONS.NOTE_DELETED'),
  conversation_logged: () =>
    t('INTEGRATION_SETTINGS.CRM_SYNC.ACTIONS.CONVERSATION_LOGGED'),
  conflict_raised: details =>
    CONFLICT_SENTENCES[details.conflict_type](details),
  conflict_resolved: () =>
    t('INTEGRATION_SETTINGS.CRM_SYNC.ACTIONS.CONFLICT_RESOLVED'),
  attributes_refreshed: () =>
    t('INTEGRATION_SETTINGS.CRM_SYNC.ACTIONS.ATTRIBUTES_REFRESHED'),
  failed: () => t('INTEGRATION_SETTINGS.CRM_SYNC.ACTIONS.FAILED'),
  rate_limited: () => t('INTEGRATION_SETTINGS.CRM_SYNC.ACTIONS.RATE_LIMITED'),
  backfill_started: () =>
    t('INTEGRATION_SETTINGS.CRM_SYNC.ACTIONS.BACKFILL_STARTED'),
  backfill_finished: details =>
    t('INTEGRATION_SETTINGS.CRM_SYNC.ACTIONS.BACKFILL_FINISHED', details),
};

const describe = ({ action, details }) => SENTENCES[action](details);

const chipLabels = computed(() => ({
  SUCCESS: t('INTEGRATION_SETTINGS.CRM_SYNC.STATUS.SUCCESS'),
  FAILURE: t('INTEGRATION_SETTINGS.CRM_SYNC.STATUS.FAILURE'),
  CONFLICT: t('INTEGRATION_SETTINGS.CRM_SYNC.STATUS.CONFLICT'),
  NOTE: t('INTEGRATION_SETTINGS.CRM_SYNC.STATUS.NOTE'),
  RATE_LIMITED: t('INTEGRATION_SETTINGS.CRM_SYNC.STATUS.RATE_LIMITED'),
}));

const chipOf = ({ action, status }) => {
  if (action === 'rate_limited') return 'RATE_LIMITED';
  if (status === 'failure') return 'FAILURE';
  if (action === 'conflict_raised') return 'CONFLICT';
  if (NOTE_ACTIONS.has(action)) return 'NOTE';
  return 'SUCCESS';
};

const fetchEvents = async (nextPage = 1) => {
  isLoadingEvents.value = true;
  eventsError.value = '';
  try {
    const { data } = await CrmSyncAPI.getEvents(props.hookId, {
      page: nextPage,
      status: onlyFailures.value ? 'failure' : undefined,
    });
    events.value =
      nextPage === 1 ? data.events : [...events.value, ...data.events];
    summary.value = data.summary;
    page.value = data.meta.page;
    hasMore.value = data.meta.has_more;
  } catch (error) {
    eventsError.value = t('INTEGRATION_SETTINGS.CRM_SYNC.EVENTS.LOAD_ERROR');
  } finally {
    isLoadingEvents.value = false;
  }
};

const isRunning = computed(() => backfill.value?.state === 'running');
const isFinished = computed(() => backfill.value?.state === 'finished');
const progress = computed(() =>
  backfill.value.total
    ? Math.round((backfill.value.processed / backfill.value.total) * 100)
    : 0
);

const finishedAt = computed(() => clockTime(backfill.value.finished_at));

const loadBackfill = async () => {
  try {
    const { data } = await CrmSyncAPI.getBackfill(props.hookId);
    backfill.value = data;
  } catch (error) {
    // Keep the last known progress; the next poll catches up.
  }
};

// Polls right away, then every POLL_INTERVAL while a run is on.
const { pause: stopPolling, resume: pollBackfill } = useTimeoutPoll(
  async () => {
    const wasRunning = isRunning.value;
    await loadBackfill();
    if (isRunning.value) return;
    stopPolling();
    // The finished run wrote its summary event and moved the counters.
    if (wasRunning) fetchEvents();
  },
  POLL_INTERVAL
);

const startBackfill = async () => {
  isStarting.value = true;
  try {
    await CrmSyncAPI.startBackfill(props.hookId);
    alreadyRunning.value = false;
    pollBackfill();
  } catch (error) {
    if (error.response?.status === 409) {
      alreadyRunning.value = true;
      pollBackfill();
    } else {
      useAlert(t('INTEGRATION_SETTINGS.CRM_SYNC.BACKFILL.START_ERROR'));
    }
  } finally {
    isStarting.value = false;
    isConfirming.value = false;
  }
};

watch(onlyFailures, () => fetchEvents());
// @vueuse/core resolves its own copy of vue, so its scope cleanup cannot be
// relied on to stop the poll.
onBeforeUnmount(stopPolling);

fetchEvents();
pollBackfill();
</script>

<template>
  <section
    class="flex flex-col outline outline-1 outline-n-container bg-n-card rounded-xl"
  >
    <header
      class="flex flex-wrap items-baseline gap-x-3 gap-y-1 px-6 py-4 border-b border-n-weak"
    >
      <h4 class="text-heading-3 text-n-slate-12">
        {{ t('INTEGRATION_SETTINGS.CRM_SYNC.TITLE') }}
      </h4>
      <span v-if="summary" class="text-sm text-n-slate-11">
        {{ lastSuccess }}
      </span>
    </header>

    <div
      v-if="summary"
      class="grid grid-cols-2 gap-4 px-6 py-4 border-b border-n-weak sm:grid-cols-4"
    >
      <div v-for="stat in stats" :key="stat.key" class="flex flex-col gap-1">
        <button
          v-if="stat.anchor"
          type="button"
          class="p-0 text-start text-heading-2 tabular-nums text-n-amber-11 hover:underline"
          @click="scrollTo(stat.anchor)"
        >
          {{ stat.value }}
        </button>
        <span
          v-else
          class="text-heading-2 tabular-nums"
          :class="stat.alert ? 'text-n-ruby-11' : 'text-n-slate-12'"
        >
          {{ stat.value }}
        </span>
        <span class="text-sm text-n-slate-11">
          {{ stat.label }}
        </span>
      </div>
    </div>

    <div class="flex flex-col gap-3 px-6 py-4 border-b border-n-weak">
      <template v-if="isRunning">
        <div class="flex items-center justify-between gap-3 text-sm">
          <span class="text-n-slate-12 tabular-nums">
            {{
              t('INTEGRATION_SETTINGS.CRM_SYNC.BACKFILL.RUNNING', {
                processed: backfill.processed,
                total: backfill.total,
              })
            }}
          </span>
          <span v-if="alreadyRunning" class="text-n-slate-11">
            {{ t('INTEGRATION_SETTINGS.CRM_SYNC.BACKFILL.ALREADY_RUNNING') }}
          </span>
        </div>
        <div class="h-1.5 overflow-hidden rounded-full bg-n-slate-4">
          <div
            data-test="backfill-progress"
            class="h-full transition-all rounded-full bg-n-brand"
            :style="{ width: `${progress}%` }"
          />
        </div>
      </template>
      <div
        v-else-if="isConfirming"
        class="flex flex-wrap items-center gap-3 text-sm"
      >
        <span class="text-n-slate-12">{{
          t('INTEGRATION_SETTINGS.CRM_SYNC.BACKFILL.CONFIRM')
        }}</span>
        <div class="flex gap-2">
          <Button
            sm
            :label="t('INTEGRATION_SETTINGS.CRM_SYNC.BACKFILL.START')"
            :is-loading="isStarting"
            @click="startBackfill"
          />
          <Button
            sm
            faded
            slate
            :label="t('INTEGRATION_SETTINGS.CRM_SYNC.BACKFILL.CANCEL')"
            @click="isConfirming = false"
          />
        </div>
      </div>
      <div v-else class="flex flex-wrap items-center gap-3">
        <Button
          sm
          faded
          slate
          :label="t('INTEGRATION_SETTINGS.CRM_SYNC.BACKFILL.BUTTON')"
          @click="isConfirming = true"
        />
        <span class="text-sm text-n-slate-11">
          {{ t('INTEGRATION_SETTINGS.CRM_SYNC.BACKFILL.DESCRIPTION') }}
        </span>
      </div>
      <p
        v-if="isRunning || isFinished"
        class="flex flex-wrap mb-0 text-sm gap-x-3 tabular-nums text-n-slate-11"
      >
        <span v-if="isFinished">
          {{
            t('INTEGRATION_SETTINGS.CRM_SYNC.BACKFILL.FINISHED', {
              time: finishedAt,
            })
          }}
        </span>
        <span>{{
          t('INTEGRATION_SETTINGS.CRM_SYNC.BACKFILL.COUNTS', backfill)
        }}</span>
      </p>
    </div>

    <div class="flex items-center justify-between gap-3 px-6 pt-4 pb-2">
      <h5 class="text-sm font-medium text-n-slate-12">
        {{ t('INTEGRATION_SETTINGS.CRM_SYNC.EVENTS.TITLE') }}
      </h5>
      <label class="flex items-center gap-2 text-sm text-n-slate-11">
        <Checkbox v-model="onlyFailures" />
        {{ t('INTEGRATION_SETTINGS.CRM_SYNC.EVENTS.ONLY_FAILURES') }}
      </label>
    </div>

    <ul v-if="events.length" class="flex flex-col m-0 list-none">
      <li
        v-for="event in events"
        :key="event.id"
        class="flex items-center gap-3 px-6 py-2.5 text-sm border-t border-n-weak"
      >
        <time
          :datetime="event.created_at"
          class="flex-shrink-0 w-24 tabular-nums text-n-slate-11"
        >
          {{ clockTime(event.created_at) }}
        </time>
        <div class="flex items-baseline flex-1 min-w-0 gap-2">
          <RouterLink
            v-if="event.contact"
            :to="contactRoute(event.contact.id)"
            class="flex-shrink-0 max-w-[40%] font-medium truncate text-n-slate-12 hover:underline"
          >
            {{ event.contact.name }}
          </RouterLink>
          <span class="min-w-0 truncate text-n-slate-11">
            {{ describe(event) }}
          </span>
          <span
            v-if="event.message"
            v-tooltip="event.message"
            class="flex-1 min-w-0 truncate text-n-ruby-11"
          >
            {{ event.message }}
          </span>
        </div>
        <span
          class="flex-shrink-0 px-1.5 py-0.5 text-xs font-medium rounded-md"
          :class="CHIP_CLASSES[chipOf(event)]"
        >
          {{ chipLabels[chipOf(event)] }}
        </span>
      </li>
    </ul>
    <div v-else-if="isLoadingEvents" class="flex justify-center px-6 py-6">
      <Spinner class="text-n-brand" />
    </div>
    <p
      v-else-if="!eventsError"
      class="px-6 py-6 mb-0 border-t text-n-slate-11 text-body-main border-n-weak"
    >
      {{
        onlyFailures
          ? t('INTEGRATION_SETTINGS.CRM_SYNC.EVENTS.EMPTY_FAILURES')
          : t('INTEGRATION_SETTINGS.CRM_SYNC.EVENTS.EMPTY')
      }}
    </p>

    <p
      v-if="eventsError"
      class="px-6 py-4 mb-0 text-sm border-t text-n-ruby-11 border-n-weak"
    >
      {{ eventsError }}
    </p>
    <div
      v-if="hasMore"
      class="flex justify-center px-6 py-4 border-t border-n-weak"
    >
      <Button
        faded
        slate
        sm
        :label="t('INTEGRATION_SETTINGS.CRM_SYNC.EVENTS.LOAD_MORE')"
        :is-loading="isLoadingEvents"
        @click="fetchEvents(page + 1)"
      />
    </div>
  </section>
</template>
