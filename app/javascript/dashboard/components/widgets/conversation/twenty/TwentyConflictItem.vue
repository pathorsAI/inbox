<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const props = defineProps({
  conflict: {
    type: Object,
    required: true,
  },
  // The Inbox contact this conflict belongs to, named in the merge warning.
  contactName: {
    type: String,
    default: '',
  },
  isResolving: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['resolve']);

const { t } = useI18n();
const route = useRoute();

const mergeDialogRef = ref(null);

const joinPresent = values => values.filter(Boolean).join(' · ');

// What the backend needs to identify this conflict, sent with every choice.
const conflictKeys = computed(() => {
  const { type, field, contact } = props.conflict;
  if (type === 'field') return { type, field };
  if (type === 'duplicate_contact')
    return { type, other_contact_id: contact.id };
  return { type };
});

const resolve = (choice, extra = {}) =>
  emit('resolve', { ...conflictKeys.value, choice, ...extra });

const fieldTitle = computed(
  () =>
    ({
      name: t('CONVERSATION_SIDEBAR.TWENTY.CONFLICTS.FIELD_TITLE.NAME'),
      email: t('CONVERSATION_SIDEBAR.TWENTY.CONFLICTS.FIELD_TITLE.EMAIL'),
      phone: t('CONVERSATION_SIDEBAR.TWENTY.CONFLICTS.FIELD_TITLE.PHONE'),
      company: t('CONVERSATION_SIDEBAR.TWENTY.CONFLICTS.FIELD_TITLE.COMPANY'),
      line_id: t('CONVERSATION_SIDEBAR.TWENTY.CONFLICTS.FIELD_TITLE.LINE_ID'),
      line_user_id: t(
        'CONVERSATION_SIDEBAR.TWENTY.CONFLICTS.FIELD_TITLE.LINE_USER_ID'
      ),
    })[props.conflict.field]
);

const candidates = computed(() =>
  props.conflict.candidates.map(candidate => ({
    ...candidate,
    label: candidate.name || candidate.email || candidate.phone,
    details: joinPresent([candidate.company, candidate.email, candidate.phone]),
  }))
);

const otherContact = computed(() => props.conflict.contact);

const otherContactName = computed(
  () =>
    otherContact.value.name ||
    otherContact.value.email ||
    otherContact.value.phone_number
);

const otherContactDetails = computed(() =>
  joinPresent([otherContact.value.email, otherContact.value.phone_number])
);

const otherContactRoute = computed(() => ({
  name: 'contacts_edit',
  params: {
    accountId: route.params.accountId,
    contactId: otherContact.value.id,
  },
}));

const mergeDescription = computed(() =>
  t('CONVERSATION_SIDEBAR.TWENTY.CONFLICTS.MERGE_DIALOG.DESCRIPTION', {
    other: otherContactName.value,
    current:
      props.contactName ||
      t('CONVERSATION_SIDEBAR.TWENTY.CONFLICTS.THIS_CONTACT'),
  })
);

const confirmMerge = () => {
  resolve('merge');
  mergeDialogRef.value.close();
};
</script>

<template>
  <div class="flex flex-col min-w-0 gap-2">
    <template v-if="conflict.type === 'field'">
      <p class="mb-0 text-sm font-medium text-n-slate-12">
        {{ fieldTitle }}
      </p>
      <dl class="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 m-0 text-sm">
        <dt class="text-n-slate-11">
          {{ t('CONVERSATION_SIDEBAR.TWENTY.CONFLICTS.INBOX') }}
        </dt>
        <dd class="min-w-0 m-0 break-words text-n-slate-12">
          {{ conflict.inbox }}
        </dd>
        <dt class="text-n-slate-11">
          {{ t('CONVERSATION_SIDEBAR.TWENTY.CONFLICTS.TWENTY') }}
        </dt>
        <dd class="min-w-0 m-0 break-words text-n-slate-12">
          {{ conflict.twenty }}
        </dd>
      </dl>
      <div class="flex flex-wrap gap-2">
        <NextButton
          faded
          slate
          xs
          :label="t('CONVERSATION_SIDEBAR.TWENTY.CONFLICTS.USE_INBOX')"
          :disabled="isResolving"
          @click="resolve('inbox')"
        />
        <NextButton
          faded
          slate
          xs
          :label="t('CONVERSATION_SIDEBAR.TWENTY.CONFLICTS.USE_TWENTY')"
          :disabled="isResolving"
          @click="resolve('twenty')"
        />
        <NextButton
          ghost
          slate
          xs
          :label="t('CONVERSATION_SIDEBAR.TWENTY.CONFLICTS.KEEP_BOTH')"
          :disabled="isResolving"
          @click="resolve('dismiss')"
        />
      </div>
    </template>

    <template v-else-if="conflict.type === 'ambiguous'">
      <p class="mb-0 text-sm font-medium text-n-slate-12">
        {{
          t('CONVERSATION_SIDEBAR.TWENTY.CONFLICTS.AMBIGUOUS_TITLE', {
            count: candidates.length,
          })
        }}
      </p>
      <ul class="flex flex-col gap-2 m-0 list-none">
        <li
          v-for="candidate in candidates"
          :key="candidate.id"
          class="flex items-start justify-between min-w-0 gap-2"
        >
          <div class="flex flex-col min-w-0">
            <a
              v-if="candidate.url"
              :href="candidate.url"
              :title="t('CONVERSATION_SIDEBAR.TWENTY.OPEN_IN_TWENTY')"
              target="_blank"
              rel="noopener noreferrer"
              class="text-sm font-medium break-words text-n-slate-12 hover:underline"
            >
              {{ candidate.label }}
            </a>
            <span
              v-else
              class="text-sm font-medium break-words text-n-slate-12"
            >
              {{ candidate.label }}
            </span>
            <span
              v-if="candidate.details"
              class="text-xs break-words text-n-slate-11"
            >
              {{ candidate.details }}
            </span>
          </div>
          <NextButton
            faded
            slate
            xs
            class="flex-shrink-0"
            :label="t('CONVERSATION_SIDEBAR.TWENTY.CONFLICTS.LINK')"
            :disabled="isResolving"
            @click="resolve('person', { person_id: candidate.id })"
          />
        </li>
      </ul>
      <div class="flex flex-wrap gap-2">
        <NextButton
          faded
          slate
          xs
          :label="t('CONVERSATION_SIDEBAR.TWENTY.CONFLICTS.CREATE_NEW')"
          :disabled="isResolving"
          @click="resolve('new')"
        />
        <NextButton
          ghost
          slate
          xs
          :label="t('CONVERSATION_SIDEBAR.TWENTY.CONFLICTS.DONT_LINK')"
          :disabled="isResolving"
          @click="resolve('dismiss')"
        />
      </div>
    </template>

    <template v-else-if="conflict.type === 'duplicate_contact'">
      <p class="mb-0 text-sm font-medium text-n-slate-12">
        {{ t('CONVERSATION_SIDEBAR.TWENTY.CONFLICTS.DUPLICATE_TITLE') }}
      </p>
      <div class="flex flex-col min-w-0">
        <RouterLink
          :to="otherContactRoute"
          :title="t('CONVERSATION_SIDEBAR.TWENTY.CONFLICTS.OPEN_CONTACT')"
          target="_blank"
          rel="noopener noreferrer"
          class="flex items-center min-w-0 gap-1.5 text-sm font-medium text-n-slate-12 hover:underline"
        >
          <span class="min-w-0 break-words">{{ otherContactName }}</span>
          <span class="flex-shrink-0 i-lucide-external-link size-3.5" />
        </RouterLink>
        <span
          v-if="otherContactDetails"
          class="text-xs break-words text-n-slate-11"
        >
          {{ otherContactDetails }}
        </span>
      </div>
      <div class="flex flex-wrap gap-2">
        <NextButton
          faded
          slate
          xs
          :label="t('CONVERSATION_SIDEBAR.TWENTY.CONFLICTS.MERGE')"
          :disabled="isResolving"
          @click="mergeDialogRef.open()"
        />
        <NextButton
          ghost
          slate
          xs
          :label="t('CONVERSATION_SIDEBAR.TWENTY.CONFLICTS.KEEP_SEPARATE')"
          :disabled="isResolving"
          @click="resolve('dismiss')"
        />
      </div>
      <Dialog
        ref="mergeDialogRef"
        type="alert"
        width="md"
        :title="t('CONVERSATION_SIDEBAR.TWENTY.CONFLICTS.MERGE_DIALOG.TITLE')"
        :description="mergeDescription"
        :confirm-button-label="
          t('CONVERSATION_SIDEBAR.TWENTY.CONFLICTS.MERGE_DIALOG.CONFIRM')
        "
        @confirm="confirmMerge"
      />
    </template>
  </div>
</template>
