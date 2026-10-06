<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRouter, useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useFunctionGetter, useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import githubAPI from 'dashboard/api/integrations/github';

import Integration from './Integration.vue';
import RepositoryForm from './Github/RepositoryForm.vue';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  setupAction: { type: String, default: '' },
  code: { type: String, default: '' },
  installationId: { type: String, default: '' },
  state: { type: String, default: '' },
});

const STATUS = {
  NOT_CONNECTED: 'not_connected',
  RECONNECT: 'reconnect',
  CHOOSE_REPOSITORY: 'choose_repository',
  CONNECTED: 'connected',
};

const store = useStore();
const router = useRouter();
const route = useRoute();
const { t } = useI18n();

const SETUP_ACTION_NOTICES = {
  request: {
    color: 'blue',
    message: t('INTEGRATION_SETTINGS.GITHUB.AWAITING_APPROVAL'),
  },
};

const CONNECT_ERROR_NOTICES = {
  installation_not_verified: {
    color: 'ruby',
    message: t('INTEGRATION_SETTINGS.GITHUB.ERRORS.INSTALLATION_NOT_VERIFIED'),
  },
  connection_failed: {
    color: 'ruby',
    message: t('INTEGRATION_SETTINGS.GITHUB.ERRORS.CONNECTION_FAILED'),
  },
};

const integrationLoaded = ref(false);
const isChangingRepository = ref(false);
const notice = ref(null);

const integration = useFunctionGetter('integrations/getIntegration', 'github');

const hook = computed(() => integration.value.hooks?.[0]);
const repository = computed(() => hook.value?.settings?.repository ?? '');
const issueLabel = computed(() => hook.value?.settings?.label ?? '');

// A hook without an installation id is a legacy token hook; it can only be
// replaced by installing the app, so it reads as not connected.
const status = computed(() => {
  if (!hook.value?.reference_id) return STATUS.NOT_CONNECTED;
  if (hook.value.reauthorization_required) return STATUS.RECONNECT;
  if (!repository.value || isChangingRepository.value) {
    return STATUS.CHOOSE_REPOSITORY;
  }
  return STATUS.CONNECTED;
});

const isConnected = computed(() => status.value !== STATUS.NOT_CONNECTED);

const repositoryUrl = computed(() => `https://github.com/${repository.value}`);

const completeInstall = async ({ code, installationId, state }) => {
  try {
    await githubAPI.connect({ code, installationId, state });
    useAlert(t('INTEGRATION_SETTINGS.GITHUB.CONNECTED_SUCCESS'));
  } catch (error) {
    notice.value =
      CONNECT_ERROR_NOTICES[error?.response?.data?.reason] ??
      CONNECT_ERROR_NOTICES.connection_failed;
  }
};

onMounted(async () => {
  // Clearing the install redirect's query also clears these props, so read
  // them first.
  const { setupAction, code, installationId, state } = props;
  notice.value = SETUP_ACTION_NOTICES[setupAction] ?? null;
  if (code && installationId && state) {
    await completeInstall({ code, installationId, state });
  }
  // The code is single-use; a reload must not submit it again.
  if (setupAction || code || installationId || state) {
    router.replace(route.path);
  }
  await store.dispatch('integrations/get', 'github');
  integrationLoaded.value = true;
});
</script>

<template>
  <SettingsLayout :is-loading="!integrationLoaded">
    <template #header>
      <BaseSettingsHeader
        :title="t('INTEGRATION_SETTINGS.GITHUB.HEADER')"
        description=""
        :back-button-label="t('INTEGRATION_SETTINGS.HEADER')"
      />
    </template>
    <template #body>
      <div class="flex flex-col gap-6">
        <Banner v-if="notice" :color="notice.color">
          {{ notice.message }}
        </Banner>
        <Integration
          :integration-id="integration.id"
          :integration-logo="integration.logo"
          :integration-name="integration.name"
          :integration-description="integration.description"
          :integration-enabled="isConnected"
          :integration-action="isConnected ? 'disconnect' : integration.action"
          :delete-confirmation-text="{
            title: t('INTEGRATION_SETTINGS.GITHUB.DELETE.TITLE'),
            message: t('INTEGRATION_SETTINGS.GITHUB.DELETE.MESSAGE'),
          }"
        />
        <Banner v-if="status === STATUS.RECONNECT" color="amber">
          <div class="flex flex-col items-start gap-2 py-1">
            <p class="m-0 font-medium">
              {{ t('INTEGRATION_SETTINGS.GITHUB.RECONNECT.TITLE') }}
            </p>
            <p class="m-0">
              {{ t('INTEGRATION_SETTINGS.GITHUB.RECONNECT.DESCRIPTION') }}
            </p>
            <a :href="integration.action">
              <Button
                amber
                sm
                :label="t('INTEGRATION_SETTINGS.GITHUB.RECONNECT.BUTTON')"
              />
            </a>
          </div>
        </Banner>
        <RepositoryForm
          v-else-if="status === STATUS.CHOOSE_REPOSITORY"
          :repository="repository"
          :label="issueLabel"
          @saved="isChangingRepository = false"
          @cancel="isChangingRepository = false"
        />
        <div
          v-else-if="status === STATUS.CONNECTED"
          class="flex flex-col gap-4 px-6 py-5 outline outline-n-container outline-1 bg-n-card rounded-xl"
        >
          <div class="flex items-start justify-between gap-4">
            <div>
              <h4 class="text-heading-3 text-n-slate-12">
                {{ t('INTEGRATION_SETTINGS.GITHUB.CONNECTED.TITLE') }}
              </h4>
              <p class="mt-1 text-n-slate-11 text-body-main">
                {{ t('INTEGRATION_SETTINGS.GITHUB.CONNECTED.DESCRIPTION') }}
              </p>
            </div>
            <Button
              faded
              slate
              sm
              :label="t('INTEGRATION_SETTINGS.GITHUB.CHANGE')"
              @click="isChangingRepository = true"
            />
          </div>
          <dl class="grid grid-cols-[auto_1fr] gap-x-6 gap-y-2 m-0">
            <dt class="text-n-slate-11 text-body-main">
              {{ t('INTEGRATION_SETTINGS.GITHUB.CONNECTED.REPOSITORY') }}
            </dt>
            <dd class="m-0 text-body-main">
              <a
                :href="repositoryUrl"
                target="_blank"
                rel="noopener noreferrer"
                class="text-n-blue-11 hover:underline"
              >
                {{ repository }}
              </a>
            </dd>
            <dt class="text-n-slate-11 text-body-main">
              {{ t('INTEGRATION_SETTINGS.GITHUB.CONNECTED.LABEL') }}
            </dt>
            <dd class="m-0 text-n-slate-12 text-body-main">
              {{
                issueLabel ||
                t('INTEGRATION_SETTINGS.GITHUB.CONNECTED.NO_LABEL')
              }}
            </dd>
          </dl>
        </div>
      </div>
    </template>
  </SettingsLayout>
</template>
