<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { frontendURL } from 'dashboard/helper/URLHelper';
import PathorsConnectionAPI from 'dashboard/api/pathorsConnection';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import RadioCard from 'dashboard/components-next/radioCard/RadioCard.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

// Entered from a Pathors organization page (`?organization_id=`). The user
// picks which account the organization should be bound to, or creates one;
// the backend checks the choice and returns the Pathors authorize URL.
const props = defineProps({
  organizationId: { type: String, default: '' },
});

const UUID_REGEX =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const NEW_ACCOUNT = 'new';
// See Pathors.vue: a public/ path has to stay a runtime string.
const PATHORS_LOGO_URL = '/dashboard/images/integrations/pathors.png';

const { t } = useI18n();

const isLoading = ref(true);
const loadFailed = ref(false);
const accounts = ref([]);
const canCreateAccount = ref(false);
const selection = ref(null);
const newAccountName = ref('');
const isSubmitting = ref(false);

const isValidLink = computed(() => UUID_REGEX.test(props.organizationId));

// Connected to a different organization, or before organizations existed:
// switching would take the account away from what it serves today, so it has
// to be disconnected on its own integration page first. The backend enforces
// the same rule.
const isBoundElsewhere = account =>
  account.connected && account.organization_id !== props.organizationId;

const accountDescription = account =>
  account.connected
    ? t('PATHORS_CONNECT.STATUS.SAME_ORGANIZATION')
    : t('PATHORS_CONNECT.STATUS.NOT_CONNECTED');

const integrationUrl = account =>
  frontendURL(`accounts/${account.id}/settings/integrations/pathors`);

const blockingMessage = computed(() => {
  if (!isValidLink.value) return t('PATHORS_CONNECT.INVALID_LINK');
  if (loadFailed.value) return t('PATHORS_CONNECT.LOAD_ERROR');
  if (!accounts.value.length && !canCreateAccount.value)
    return t('PATHORS_CONNECT.NO_ACCOUNTS');
  return '';
});

const canContinue = computed(() => {
  if (selection.value === NEW_ACCOUNT)
    return newAccountName.value.trim().length > 0;
  return selection.value !== null;
});

const requestAuthorizeUrl = async () => {
  if (selection.value === NEW_ACCOUNT) {
    const { data } = await PathorsConnectionAPI.createAccount({
      accountName: newAccountName.value.trim(),
      organizationId: props.organizationId,
    });
    return data.authorize_url;
  }
  const { data } = await PathorsConnectionAPI.connect({
    accountId: selection.value,
    organizationId: props.organizationId,
  });
  return data.authorize_url;
};

const continueToPathors = async () => {
  isSubmitting.value = true;
  try {
    window.location.assign(await requestAuthorizeUrl());
  } catch (error) {
    useAlert(error?.response?.data?.error || t('PATHORS_CONNECT.ERROR'));
    isSubmitting.value = false;
  }
};

const loadAccounts = async () => {
  try {
    const { data } = await PathorsConnectionAPI.get();
    accounts.value = data.accounts;
    canCreateAccount.value = data.can_create_account;
    if (!data.accounts.length && data.can_create_account) {
      selection.value = NEW_ACCOUNT;
    }
  } catch {
    loadFailed.value = true;
  } finally {
    isLoading.value = false;
  }
};

onMounted(() => {
  if (isValidLink.value) {
    loadAccounts();
  } else {
    isLoading.value = false;
  }
});
</script>

<template>
  <main
    class="flex flex-col items-center flex-1 w-full px-4 py-16 overflow-y-auto bg-n-background"
  >
    <section class="flex flex-col w-full max-w-lg gap-6">
      <header class="flex flex-col items-center gap-3 text-center">
        <img
          :src="PATHORS_LOGO_URL"
          alt=""
          class="border rounded-lg size-12 border-n-weak"
        />
        <h1 class="text-heading-1 text-n-slate-12">
          {{ t('PATHORS_CONNECT.TITLE') }}
        </h1>
        <p class="text-body-main text-n-slate-11">
          {{ t('PATHORS_CONNECT.DESCRIPTION') }}
        </p>
      </header>

      <div v-if="isLoading" class="flex justify-center py-8 text-n-slate-10">
        <Spinner />
      </div>

      <p
        v-else-if="blockingMessage"
        class="p-4 outline outline-1 outline-n-container bg-n-card rounded-xl text-body-main text-n-slate-11"
      >
        {{ blockingMessage }}
      </p>

      <form
        v-else
        class="flex flex-col gap-3"
        @submit.prevent="continueToPathors"
      >
        <RadioCard
          v-for="account in accounts"
          :id="`pathors-connect-account-${account.id}`"
          :key="account.id"
          name="pathors-connect-account"
          :label="account.name"
          :description="accountDescription(account)"
          :is-active="selection === account.id"
          :disabled="isBoundElsewhere(account)"
          :disabled-label="t('PATHORS_CONNECT.STATUS.OTHER_ORGANIZATION')"
          :disabled-message="t('PATHORS_CONNECT.OTHER_ORGANIZATION_HINT')"
          @select="selection = account.id"
        >
          <template v-if="isBoundElsewhere(account)">
            <span
              v-if="account.organization_id"
              class="font-mono break-all text-label-small text-n-slate-11"
            >
              {{
                t('PATHORS_CONNECT.ORGANIZATION_ID', {
                  id: account.organization_id,
                })
              }}
            </span>
            <a
              :href="integrationUrl(account)"
              class="underline text-label-small text-n-blue-11"
            >
              {{ t('PATHORS_CONNECT.OPEN_INTEGRATION') }}
            </a>
          </template>
        </RadioCard>

        <RadioCard
          v-if="canCreateAccount"
          id="pathors-connect-new-account"
          name="pathors-connect-account"
          :label="t('PATHORS_CONNECT.NEW_ACCOUNT.LABEL')"
          :description="t('PATHORS_CONNECT.NEW_ACCOUNT.DESCRIPTION')"
          :is-active="selection === NEW_ACCOUNT"
          @select="selection = NEW_ACCOUNT"
        />
        <!-- Outside the card: the card is a <label>, and Input brings its own -->
        <Input
          v-if="selection === NEW_ACCOUNT"
          v-model="newAccountName"
          :label="t('PATHORS_CONNECT.NEW_ACCOUNT.NAME_LABEL')"
          :placeholder="t('PATHORS_CONNECT.NEW_ACCOUNT.NAME_PLACEHOLDER')"
          autofocus
        />

        <Button
          type="submit"
          class="w-full mt-3"
          :label="t('PATHORS_CONNECT.CONTINUE')"
          :disabled="!canContinue || isSubmitting"
          :is-loading="isSubmitting"
        />
      </form>
    </section>
  </main>
</template>
