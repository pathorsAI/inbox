<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { format } from 'date-fns';
import camelcaseKeys from 'camelcase-keys';
import CallsAPI from 'dashboard/api/calls';
import ContactAPI from 'dashboard/api/contacts';
import { outcomeLabelKey, toEpochMs } from 'dashboard/helper/pathorsCallState';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

// The caller behind a call: who they are, their labels and their earlier
// calls, opened from the number in the sheet's title. The contact page is a
// link away for anything more.

const props = defineProps({
  call: { type: Object, required: true },
  accountId: { type: Number, required: true },
  // The sheet's title, shown as the trigger.
  title: { type: String, required: true },
});

const emit = defineEmits(['openCall']);

const EARLIER_CALLS_SHOWN = 5;
const CALL_TIME_FORMAT = 'MM/dd HH:mm';

const { t } = useI18n();

// A list row nests the contact; a live store record flattens it.
const contact = computed(() => {
  if (props.call.contact) return props.call.contact;
  if (!props.call.contactId) return null;
  return {
    id: props.call.contactId,
    name: props.call.contactName,
    phoneNumber: props.call.contactPhoneNumber,
  };
});
const labels = ref([]);
const earlierCalls = ref([]);
const isLoading = ref(false);
const hasLoadError = ref(false);

const contactRoute = computed(() => ({
  name: 'contacts_edit',
  params: { accountId: props.accountId, contactId: contact.value?.id },
}));

const callTime = call => {
  const at = toEpochMs(call.startedAt ?? call.createdAt);
  return at ? format(new Date(at), CALL_TIME_FORMAT) : '';
};

const load = async () => {
  const contactId = contact.value?.id;
  if (!contactId) return;
  isLoading.value = true;
  hasLoadError.value = false;
  try {
    const [labelsResponse, callsResponse] = await Promise.all([
      ContactAPI.getContactLabels(contactId),
      CallsAPI.get({ contact_id: contactId }),
    ]);
    labels.value = labelsResponse.data.payload;
    earlierCalls.value = camelcaseKeys(callsResponse.data.payload, {
      deep: true,
      stopPaths: ['variables'],
    })
      .filter(item => item.id !== props.call.id)
      .slice(0, EARLIER_CALLS_SHOWN);
  } catch {
    hasLoadError.value = true;
  } finally {
    isLoading.value = false;
  }
};

const openCall = (item, hide) => {
  hide();
  emit('openCall', item.id);
};
</script>

<template>
  <h2
    v-if="!contact"
    class="text-base font-medium truncate text-n-slate-12"
    data-test-id="call-title"
  >
    {{ title }}
  </h2>
  <Popover v-else align="start" @show="load">
    <button
      type="button"
      class="flex items-center min-w-0 gap-1 text-base font-medium text-start text-n-slate-12 hover:underline"
      data-test-id="call-contact-trigger"
    >
      <span class="truncate">{{ title }}</span>
      <Icon icon="i-lucide-chevron-down" class="size-4 shrink-0" />
    </button>
    <template #content="{ hide }">
      <div
        class="flex flex-col gap-4 p-4 w-72"
        data-test-id="call-contact-card"
      >
        <div class="flex flex-col gap-0.5 min-w-0">
          <span class="text-sm font-medium truncate text-n-slate-12">
            {{ contact.name || t('CALLS_PAGE.TABLE.UNKNOWN_CALLER') }}
          </span>
          <span
            v-if="contact.phoneNumber"
            class="text-sm tabular-nums text-n-slate-11"
          >
            {{ contact.phoneNumber }}
          </span>
        </div>

        <p v-if="isLoading" class="text-sm text-n-slate-10">
          {{ t('CALLS_PAGE.CONTACT.LOADING') }}
        </p>
        <p v-else-if="hasLoadError" class="text-sm text-n-ruby-11">
          {{ t('CALLS_PAGE.CONTACT.LOAD_FAILED') }}
        </p>
        <template v-else>
          <section class="flex flex-col gap-1.5">
            <h3 class="text-xs font-medium text-n-slate-11">
              {{ t('CALLS_PAGE.CONTACT.LABELS') }}
            </h3>
            <div v-if="labels.length" class="flex flex-wrap gap-1">
              <span
                v-for="label in labels"
                :key="label"
                class="px-1.5 text-xs leading-5 rounded-md bg-n-alpha-2 text-n-slate-12"
              >
                {{ label }}
              </span>
            </div>
            <p v-else class="text-sm text-n-slate-10">
              {{ t('CALLS_PAGE.CONTACT.NO_LABELS') }}
            </p>
          </section>

          <section class="flex flex-col gap-1.5">
            <h3 class="text-xs font-medium text-n-slate-11">
              {{ t('CALLS_PAGE.CONTACT.EARLIER_CALLS') }}
            </h3>
            <ul v-if="earlierCalls.length" class="flex flex-col">
              <li v-for="item in earlierCalls" :key="item.id">
                <button
                  type="button"
                  class="flex items-center justify-between w-full gap-3 px-2 py-1 -mx-2 text-sm rounded-md text-start hover:bg-n-alpha-1"
                  data-test-id="call-contact-earlier-call"
                  @click="openCall(item, hide)"
                >
                  <span class="tabular-nums text-n-slate-11">
                    {{ callTime(item) }}
                  </span>
                  <span class="truncate text-n-slate-12">
                    {{ t(outcomeLabelKey(item.outcome)) }}
                  </span>
                </button>
              </li>
            </ul>
            <p v-else class="text-sm text-n-slate-10">
              {{ t('CALLS_PAGE.CONTACT.NO_EARLIER_CALLS') }}
            </p>
          </section>
        </template>

        <RouterLink
          :to="contactRoute"
          class="inline-flex items-center gap-1 text-sm text-n-blue-11 hover:underline"
          data-test-id="call-contact-open"
        >
          {{ t('CALLS_PAGE.CONTACT.OPEN_CONTACT') }}
          <Icon icon="i-lucide-arrow-up-right" class="size-3.5" />
        </RouterLink>
      </div>
    </template>
  </Popover>
</template>
