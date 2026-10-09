<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { isPathorsLoginEnabled } from 'shared/helpers/pathorsLogin';
import EmptyState from 'dashboard/components/widgets/EmptyState.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Auth from 'dashboard/api/auth';

const { t } = useI18n();
const store = useStore();
const isOnChatwootCloud = useMapGetter('globalConfig/isOnChatwootCloud');
const currentUser = useMapGetter('getCurrentUser');

const canCreateAccount = globalThis.chatwootConfig?.signupEnabled === 'true';
const accountName = ref('');
const isCreating = ref(false);

const message = computed(() => {
  if (isPathorsLoginEnabled()) {
    return t('APP_GLOBAL.NO_ACCOUNTS.MESSAGE_PATHORS_INVITE', {
      email: currentUser.value?.email,
    });
  }
  if (isOnChatwootCloud.value) {
    return t('APP_GLOBAL.NO_ACCOUNTS.MESSAGE_CLOUD');
  }
  return t('APP_GLOBAL.NO_ACCOUNTS.MESSAGE_SELF_HOSTED');
});

const createAccount = async () => {
  isCreating.value = true;
  try {
    const accountId = await store.dispatch('accounts/create', {
      account_name: accountName.value.trim(),
    });
    globalThis.location = `/app/accounts/${accountId}/dashboard`;
  } catch (error) {
    isCreating.value = false;
    useAlert(
      error?.response?.status === 422
        ? t('CREATE_ACCOUNT.API.EXIST_MESSAGE')
        : t('CREATE_ACCOUNT.API.ERROR_MESSAGE')
    );
  }
};

const handleLogout = () => {
  Auth.logout();
};
</script>

<template>
  <div
    class="flex flex-col flex-1 items-center justify-center w-full h-full gap-6 bg-n-slate-2"
  >
    <form
      v-if="canCreateAccount"
      class="flex flex-col w-full max-w-sm gap-4"
      data-testid="create-account-form"
      @submit.prevent="createAccount"
    >
      <h3 class="text-xl font-medium text-center text-n-slate-12">
        {{ $t('APP_GLOBAL.NO_ACCOUNTS.CREATE.TITLE') }}
      </h3>
      <p class="text-sm text-center text-n-slate-11">
        {{ $t('APP_GLOBAL.NO_ACCOUNTS.CREATE.MESSAGE') }}
      </p>
      <Input
        v-model="accountName"
        autofocus
        :label="$t('CREATE_ACCOUNT.FORM.NAME.LABEL')"
        :placeholder="$t('CREATE_ACCOUNT.FORM.NAME.PLACEHOLDER')"
      />
      <NextButton
        type="submit"
        class="w-full"
        :label="$t('APP_GLOBAL.NO_ACCOUNTS.CREATE.SUBMIT')"
        :is-loading="isCreating"
        :disabled="!accountName.trim() || isCreating"
      />
    </form>
    <EmptyState
      v-else
      :title="$t('APP_GLOBAL.NO_ACCOUNTS.TITLE')"
      :message="message"
    />
    <NextButton
      variant="smooth"
      color-scheme="secondary"
      :label="$t('APP_GLOBAL.NO_ACCOUNTS.LOGOUT')"
      @click="handleLogout"
    />
  </div>
</template>
