<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import githubAPI from 'dashboard/api/integrations/github';

import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  repository: { type: String, default: '' },
  label: { type: String, default: '' },
});

const emit = defineEmits(['saved', 'cancel']);

const store = useStore();
const { t } = useI18n();

const repositories = ref([]);
const isLoadingRepositories = ref(true);
const isSaving = ref(false);
const repositoryError = ref('');
const selectedRepository = ref(props.repository);
const issueLabel = ref(props.label);

const repositoryOptions = computed(() =>
  repositories.value.map(name => ({ value: name, label: name }))
);

const repositoryMessage = computed(() => {
  if (repositoryError.value) return repositoryError.value;
  if (isLoadingRepositories.value) {
    return t('INTEGRATION_SETTINGS.GITHUB.REPOSITORY.LOADING');
  }
  if (!repositories.value.length) {
    return t('INTEGRATION_SETTINGS.GITHUB.REPOSITORY.EMPTY');
  }
  return t('INTEGRATION_SETTINGS.GITHUB.REPOSITORY.HELP');
});

const canSave = computed(
  () => Boolean(selectedRepository.value) && !isSaving.value
);

const loadRepositories = async () => {
  try {
    const { data } = await githubAPI.getRepositories();
    repositories.value = data;
  } catch {
    repositoryError.value = t(
      'INTEGRATION_SETTINGS.GITHUB.REPOSITORY.LOAD_ERROR'
    );
    // A refused listing marks the hook reauthorization_required server-side;
    // refetching lets the page switch to the reconnect state.
    await store.dispatch('integrations/get', 'github');
  } finally {
    isLoadingRepositories.value = false;
  }
};

const save = async () => {
  if (!canSave.value) return;
  isSaving.value = true;
  repositoryError.value = '';
  try {
    await githubAPI.updateSettings({
      repository: selectedRepository.value,
      label: issueLabel.value.trim(),
    });
    useAlert(t('INTEGRATION_SETTINGS.GITHUB.UPDATE_SUCCESS'));
    await store.dispatch('integrations/get', 'github');
    emit('saved');
  } catch (error) {
    repositoryError.value =
      error?.response?.data?.error ||
      t('INTEGRATION_SETTINGS.GITHUB.UPDATE_ERROR');
  } finally {
    isSaving.value = false;
  }
};

onMounted(() => {
  loadRepositories();
});
</script>

<template>
  <div
    class="flex flex-col gap-5 px-6 py-5 outline outline-n-container outline-1 bg-n-card rounded-xl"
  >
    <div>
      <h4 class="text-heading-3 text-n-slate-12">
        {{ t('INTEGRATION_SETTINGS.GITHUB.FORM.TITLE') }}
      </h4>
      <p class="mt-1 text-n-slate-11 text-body-main">
        {{ t('INTEGRATION_SETTINGS.GITHUB.FORM.DESCRIPTION') }}
      </p>
    </div>
    <div class="flex flex-col max-w-xl gap-1">
      <span class="mb-0.5 text-heading-3 text-n-slate-12">
        {{ t('INTEGRATION_SETTINGS.GITHUB.REPOSITORY.LABEL') }}
      </span>
      <ComboBox
        v-model="selectedRepository"
        :options="repositoryOptions"
        :display-label="selectedRepository"
        :placeholder="t('INTEGRATION_SETTINGS.GITHUB.REPOSITORY.PLACEHOLDER')"
        :search-placeholder="
          t('INTEGRATION_SETTINGS.GITHUB.REPOSITORY.SEARCH_PLACEHOLDER')
        "
        :empty-state="t('INTEGRATION_SETTINGS.GITHUB.REPOSITORY.NO_MATCH')"
        :disabled="isLoadingRepositories"
        :message="repositoryMessage"
        :has-error="Boolean(repositoryError)"
      />
    </div>
    <Input
      v-model="issueLabel"
      class="max-w-xl"
      :label="t('INTEGRATION_SETTINGS.GITHUB.LABEL.LABEL')"
      :placeholder="t('INTEGRATION_SETTINGS.GITHUB.LABEL.PLACEHOLDER')"
      :message="t('INTEGRATION_SETTINGS.GITHUB.LABEL.HELP')"
      @enter="save"
    />
    <div class="flex items-center gap-2">
      <Button
        :label="t('INTEGRATION_SETTINGS.GITHUB.SAVE')"
        :is-loading="isSaving"
        :disabled="!canSave"
        @click="save"
      />
      <Button
        v-if="repository"
        faded
        slate
        :label="t('INTEGRATION_SETTINGS.GITHUB.CANCEL')"
        :disabled="isSaving"
        @click="emit('cancel')"
      />
    </div>
  </div>
</template>
