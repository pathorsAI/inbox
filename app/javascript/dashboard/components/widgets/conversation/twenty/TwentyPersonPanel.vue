<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import TwentyAPI from 'dashboard/api/integrations/twenty';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import TwentyOpportunityItem from './TwentyOpportunityItem.vue';
import TwentyNoteItem from './TwentyNoteItem.vue';
import TwentyConflictItem from './TwentyConflictItem.vue';

const props = defineProps({
  contactId: {
    type: [Number, String],
    required: true,
  },
  contactName: {
    type: String,
    default: '',
  },
});

const { t } = useI18n();

const record = ref(null);
const errorMessage = ref('');

// Each request keeps only its latest call alive, so switching conversations
// never renders a CRM record fetched, created or resolved for the previous
// contact.
// Loading is read from `record` rather than the fetch's isPending, which
// clears a tick before the response is assigned.
const { run: runFetch } = useAbortableRequest();
const {
  run: runCreate,
  abort: abortCreate,
  isPending: isCreating,
} = useAbortableRequest();
const {
  run: runResolve,
  abort: abortResolve,
  isPending: isResolving,
} = useAbortableRequest();

// 429: Twenty throttled us; 502: Twenty is down. Either way it is Twenty,
// not this inbox, and trying again shortly is the fix.
const TWENTY_UNAVAILABLE = new Set([429, 502]);

const person = computed(() => record.value.person);

// "None of these — add new" on the candidates replaces the plain Add button.
const hasAmbiguousConflict = computed(() =>
  record.value.conflicts.some(conflict => conflict.type === 'ambiguous')
);

const contactRows = computed(() =>
  [
    { icon: 'i-lucide-map-pin', value: person.value.city },
    {
      icon: 'i-lucide-mail',
      value: person.value.email,
      href: `mailto:${person.value.email}`,
    },
    {
      icon: 'i-lucide-phone',
      value: person.value.phone,
      href: `tel:${person.value.phone}`,
    },
  ].filter(row => row.value)
);

const hasMoreNotes = computed(
  () => record.value.notes_count > record.value.notes.length
);

const fetchRecord = async () => {
  record.value = null;
  errorMessage.value = '';
  try {
    const response = await runFetch(signal =>
      TwentyAPI.getPerson(props.contactId, { signal })
    );
    if (response) record.value = response.data;
  } catch (error) {
    errorMessage.value = TWENTY_UNAVAILABLE.has(error.response?.status)
      ? t('CONVERSATION_SIDEBAR.TWENTY.UNAVAILABLE')
      : t('CONVERSATION_SIDEBAR.TWENTY.LOAD_ERROR');
  }
};

const createPerson = async () => {
  try {
    const response = await runCreate(signal =>
      TwentyAPI.createPerson(props.contactId, { signal })
    );
    if (response) record.value = response.data;
  } catch (error) {
    const { status, data } = error.response || {};
    // A 422 carries a translated reason (e.g. the contact has no email or phone).
    if (status === 422) useAlert(data.error);
    else if (TWENTY_UNAVAILABLE.has(status))
      useAlert(t('CONVERSATION_SIDEBAR.TWENTY.UNAVAILABLE'));
    else useAlert(t('CONVERSATION_SIDEBAR.TWENTY.CREATE_ERROR'));
  }
};

const resolveErrorMessage = error => {
  const { status, data } = error.response || {};
  // A 422 carries a translated reason (e.g. another contact has this email).
  if (status === 422) return data.error;
  if (TWENTY_UNAVAILABLE.has(status))
    return t('CONVERSATION_SIDEBAR.TWENTY.UNAVAILABLE');
  return t('CONVERSATION_SIDEBAR.TWENTY.CONFLICTS.RESOLVE_ERROR');
};

const resolveConflict = async payload => {
  try {
    const response = await runResolve(signal =>
      TwentyAPI.resolveConflict(
        { contact_id: props.contactId, ...payload },
        { signal }
      )
    );
    if (response) record.value = response.data;
  } catch (error) {
    useAlert(resolveErrorMessage(error));
  }
};

watch(
  () => props.contactId,
  () => {
    abortCreate();
    abortResolve();
    fetchRecord();
  },
  { immediate: true }
);
</script>

<template>
  <div class="px-4 py-3">
    <p v-if="errorMessage" class="mb-0 text-sm text-center text-n-slate-11">
      {{ errorMessage }}
    </p>
    <div v-else-if="!record" class="flex justify-center p-4">
      <Spinner class="text-n-brand" />
    </div>
    <div v-else class="flex flex-col gap-4">
      <section
        v-if="record.conflicts.length"
        class="flex flex-col gap-2 p-3 border rounded-lg border-n-amber-4 bg-n-amber-2"
      >
        <h4
          class="mb-0 text-xs font-semibold tracking-wider uppercase text-n-amber-11"
        >
          {{ t('CONVERSATION_SIDEBAR.TWENTY.CONFLICTS.HEADING') }}
          <span class="font-medium tracking-normal normal-case ms-1">
            {{ record.conflicts.length }}
          </span>
        </h4>
        <ul class="flex flex-col gap-3 m-0 list-none">
          <li
            v-for="conflict in record.conflicts"
            :key="conflict.field || conflict.contact?.id || conflict.type"
            class="pt-3 border-t border-n-amber-4 first:pt-0 first:border-t-0"
          >
            <TwentyConflictItem
              :conflict="conflict"
              :contact-name="contactName"
              :is-resolving="isResolving"
              @resolve="resolveConflict"
            />
          </li>
        </ul>
      </section>

      <div v-if="!record.linked" class="flex flex-col items-start gap-2">
        <p class="mb-0 text-sm text-n-slate-11">
          {{ t('CONVERSATION_SIDEBAR.TWENTY.NOT_LINKED') }}
        </p>
        <NextButton
          v-if="record.can_create && !hasAmbiguousConflict"
          ghost
          xs
          icon="i-lucide-plus"
          :label="t('CONVERSATION_SIDEBAR.TWENTY.ADD_TO_TWENTY')"
          :is-loading="isCreating"
          @click="createPerson"
        />
      </div>

      <template v-else>
        <section class="flex flex-col min-w-0 gap-1">
          <a
            :href="person.url"
            :title="t('CONVERSATION_SIDEBAR.TWENTY.OPEN_IN_TWENTY')"
            target="_blank"
            rel="noopener noreferrer"
            class="flex items-center min-w-0 gap-1.5 text-sm font-semibold text-n-slate-12 hover:underline"
          >
            <span class="truncate">
              {{ person.name || person.email || person.phone }}
            </span>
            <span class="flex-shrink-0 i-lucide-external-link size-3.5" />
          </a>
          <p
            v-if="person.job_title || person.company"
            class="flex items-center min-w-0 gap-1.5 mb-0 text-sm text-n-slate-11"
          >
            <span v-if="person.job_title" class="truncate">
              {{ person.job_title }}
            </span>
            <span v-if="person.job_title && person.company">·</span>
            <a
              v-if="person.company"
              :href="person.company.url"
              target="_blank"
              rel="noopener noreferrer"
              class="truncate hover:underline"
            >
              {{ person.company.name }}
            </a>
          </p>
          <ul
            v-if="contactRows.length"
            class="flex flex-col gap-1 m-0 mt-1 list-none"
          >
            <li
              v-for="row in contactRows"
              :key="row.icon"
              class="flex items-center min-w-0 gap-2 text-sm text-n-slate-11"
            >
              <span class="flex-shrink-0 size-3.5" :class="row.icon" />
              <a
                v-if="row.href"
                :href="row.href"
                class="truncate hover:underline"
              >
                {{ row.value }}
              </a>
              <span v-else class="truncate">{{ row.value }}</span>
            </li>
          </ul>
        </section>

        <section
          v-if="record.opportunities.length"
          class="flex flex-col gap-2 pt-3 border-t border-n-weak"
        >
          <h4
            class="mb-0 text-xs font-semibold tracking-wider uppercase text-n-slate-11"
          >
            {{ t('CONVERSATION_SIDEBAR.TWENTY.OPPORTUNITIES') }}
            <span
              class="font-medium tracking-normal normal-case ms-1 text-n-slate-10"
            >
              {{ record.opportunities.length }}
            </span>
          </h4>
          <ul class="flex flex-col gap-3 m-0 list-none">
            <li
              v-for="opportunity in record.opportunities"
              :key="opportunity.id"
            >
              <TwentyOpportunityItem :opportunity="opportunity" />
            </li>
          </ul>
        </section>

        <section
          v-if="record.notes.length"
          class="flex flex-col gap-2 pt-3 border-t border-n-weak"
        >
          <h4
            class="mb-0 text-xs font-semibold tracking-wider uppercase text-n-slate-11"
          >
            {{ t('CONVERSATION_SIDEBAR.TWENTY.NOTES') }}
            <span
              class="font-medium tracking-normal normal-case ms-1 text-n-slate-10"
            >
              {{ record.notes_count }}
            </span>
          </h4>
          <ul class="flex flex-col gap-3 m-0 list-none">
            <li v-for="note in record.notes" :key="note.id">
              <TwentyNoteItem :note="note" />
            </li>
          </ul>
          <a
            v-if="hasMoreNotes"
            :href="person.url"
            target="_blank"
            rel="noopener noreferrer"
            class="self-start text-sm font-medium text-n-blue-11 hover:underline"
          >
            {{ t('CONVERSATION_SIDEBAR.TWENTY.VIEW_ALL_NOTES') }}
          </a>
        </section>
      </template>
    </div>
  </div>
</template>
