<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import TwentyAPI from 'dashboard/api/integrations/twenty';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import TwentyConflictItem from 'dashboard/components/widgets/conversation/twenty/TwentyConflictItem.vue';

// 429: Twenty throttled us; 502: Twenty is down.
const TWENTY_UNAVAILABLE = new Set([429, 502]);

const PER_PAGE = 25;

const { t } = useI18n();
const route = useRoute();

const contacts = ref([]);
const count = ref(0);
const hasLoaded = ref(false);
const isLoading = ref(false);
const errorMessage = ref('');
const resolvingIds = ref(new Set());

const hasMore = computed(
  () => hasLoaded.value && contacts.value.length < count.value
);

const displayName = contact =>
  contact.name || contact.email || contact.phone_number;

const contactRoute = contactId => ({
  name: 'contacts_edit',
  params: { accountId: route.params.accountId, contactId },
});

// Resolved contacts leave the server list too, so the next page is counted
// from what is still loaded; rows the server shifted back are skipped by id.
const loadMore = async () => {
  isLoading.value = true;
  errorMessage.value = '';
  try {
    const { data } = await TwentyAPI.getConflicts(
      Math.floor(contacts.value.length / PER_PAGE) + 1
    );
    const loadedIds = new Set(contacts.value.map(({ id }) => id));
    contacts.value.push(
      ...data.contacts.filter(({ id }) => !loadedIds.has(id))
    );
    count.value = data.count;
    hasLoaded.value = true;
  } catch (error) {
    errorMessage.value = TWENTY_UNAVAILABLE.has(error.response?.status)
      ? t('CONVERSATION_SIDEBAR.TWENTY.UNAVAILABLE')
      : t('INTEGRATION_SETTINGS.TWENTY.CONFLICTS.LOAD_ERROR');
  } finally {
    isLoading.value = false;
  }
};

const dropContact = contactId => {
  if (!contacts.value.some(({ id }) => id === contactId)) return;
  contacts.value = contacts.value.filter(({ id }) => id !== contactId);
  count.value -= 1;
};

const resolveErrorMessage = error => {
  const { status, data } = error.response || {};
  // A 422 carries a translated reason (e.g. another contact has this email).
  if (status === 422) return data.error;
  if (TWENTY_UNAVAILABLE.has(status))
    return t('CONVERSATION_SIDEBAR.TWENTY.UNAVAILABLE');
  return t('CONVERSATION_SIDEBAR.TWENTY.CONFLICTS.RESOLVE_ERROR');
};

const resolveConflict = async (contactId, payload) => {
  resolvingIds.value.add(contactId);
  try {
    const { data } = await TwentyAPI.resolveConflict({
      contact_id: contactId,
      ...payload,
    });
    // A merged contact is deleted, so its own row goes as well.
    if (payload.choice === 'merge') dropContact(payload.other_contact_id);
    if (data.conflicts.length) {
      contacts.value.find(({ id }) => id === contactId).conflicts =
        data.conflicts;
    } else {
      dropContact(contactId);
    }
  } catch (error) {
    useAlert(resolveErrorMessage(error));
  } finally {
    resolvingIds.value.delete(contactId);
  }
};

loadMore();
</script>

<template>
  <section
    class="flex flex-col outline outline-1 outline-n-container bg-n-card rounded-xl"
  >
    <header class="flex flex-col gap-1 px-6 py-4 border-b border-n-weak">
      <h4 class="flex items-center gap-2 text-heading-3 text-n-slate-12">
        {{ t('INTEGRATION_SETTINGS.TWENTY.CONFLICTS.TITLE') }}
        <span v-if="count" class="tabular-nums text-n-slate-11">
          {{ count }}
        </span>
      </h4>
      <p class="mb-0 text-n-slate-11 text-body-main">
        {{ t('INTEGRATION_SETTINGS.TWENTY.CONFLICTS.DESCRIPTION') }}
      </p>
    </header>

    <ul v-if="contacts.length" class="flex flex-col m-0 list-none">
      <li
        v-for="contact in contacts"
        :key="contact.id"
        class="flex flex-col gap-3 px-6 py-4 border-b border-n-weak last:border-b-0 lg:flex-row lg:gap-6"
      >
        <div class="flex items-start flex-shrink-0 min-w-0 gap-3 lg:w-64">
          <Avatar
            :src="contact.thumbnail"
            :name="displayName(contact)"
            :size="32"
            rounded-full
          />
          <div class="flex flex-col min-w-0">
            <RouterLink
              :to="contactRoute(contact.id)"
              :title="t('CONVERSATION_SIDEBAR.TWENTY.CONFLICTS.OPEN_CONTACT')"
              target="_blank"
              rel="noopener noreferrer"
              class="font-medium truncate text-body-main text-n-slate-12 hover:underline"
            >
              {{ displayName(contact) }}
            </RouterLink>
            <span v-if="contact.email" class="text-sm truncate text-n-slate-11">
              {{ contact.email }}
            </span>
            <span
              v-if="contact.phone_number"
              class="text-sm truncate text-n-slate-11"
            >
              {{ contact.phone_number }}
            </span>
          </div>
        </div>
        <ul class="flex flex-col flex-1 min-w-0 gap-4 m-0 list-none">
          <li
            v-for="conflict in contact.conflicts"
            :key="conflict.field || conflict.contact?.id || conflict.type"
          >
            <TwentyConflictItem
              :conflict="conflict"
              :contact-name="displayName(contact)"
              :is-resolving="resolvingIds.has(contact.id)"
              @resolve="payload => resolveConflict(contact.id, payload)"
            />
          </li>
        </ul>
      </li>
    </ul>
    <p
      v-else-if="hasLoaded"
      class="px-6 py-6 mb-0 text-n-slate-11 text-body-main"
    >
      {{ t('INTEGRATION_SETTINGS.TWENTY.CONFLICTS.EMPTY') }}
    </p>
    <div v-else-if="isLoading" class="flex justify-center px-6 py-6">
      <Spinner class="text-n-brand" />
    </div>

    <p v-if="errorMessage" class="px-6 py-4 mb-0 text-sm text-n-ruby-11">
      {{ errorMessage }}
    </p>
    <div
      v-if="hasMore"
      class="flex justify-center px-6 py-4 border-t border-n-weak"
    >
      <Button
        faded
        slate
        sm
        :label="t('INTEGRATION_SETTINGS.TWENTY.CONFLICTS.LOAD_MORE')"
        :is-loading="isLoading"
        @click="loadMore"
      />
    </div>
  </section>
</template>
