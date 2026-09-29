<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import QuickFilterOptions from './QuickFilterOptions.vue';
import { QUICK_FILTER, daysAgo, lastActivityPreset } from './conditions';

const props = defineProps({
  pill: { type: String, required: true },
  // The pill's current value (see readQuickFilters), null while unset.
  value: { type: [String, Array], default: null },
  // [{ value, label }]; empty for the free-text company pill.
  options: { type: Array, default: () => [] },
});

// An empty value clears the pill.
const emit = defineEmits(['apply', 'clear']);

const { t } = useI18n();

const isLastActivity = props.pill === QUICK_FILTER.LAST_ACTIVITY;
const isLabels = props.pill === QUICK_FILTER.LABELS;
const isCompany = props.pill === QUICK_FILTER.COMPANY;
const isCountry = props.pill === QUICK_FILTER.COUNTRY;

const preset = isLastActivity && props.value && lastActivityPreset(props.value);

// Drafts, applied with the Apply button or Enter.
const text = ref(isCompany ? (props.value ?? '') : '');
const customDate = ref(isLastActivity && !preset ? (props.value ?? '') : '');
const selectedLabels = ref(isLabels ? [...(props.value ?? [])] : []);

const searchPlaceholder = computed(() => {
  if (isLabels) return t('CONTACTS_LAYOUT.FILTER.QUICK.LABELS.SEARCH');
  if (isCountry) return t('CONTACTS_LAYOUT.FILTER.QUICK.COUNTRY.SEARCH');
  return '';
});

const selected = computed(() => {
  if (isLabels) return selectedLabels.value;
  if (isLastActivity) return [preset?.days];
  return [props.value];
});

const apply = value => {
  if (value.length) emit('apply', value);
  else emit('clear');
};

const toggleLabel = title => {
  const titles = new Set(selectedLabels.value);
  if (titles.has(title)) titles.delete(title);
  else titles.add(title);
  selectedLabels.value = [...titles];
};

const onSelect = value => {
  if (isLabels) toggleLabel(value);
  else if (isLastActivity) apply(daysAgo(value));
  else apply(value);
};
</script>

<template>
  <div class="flex flex-col gap-2 min-w-0">
    <form
      v-if="isCompany"
      class="flex items-center gap-2"
      @submit.prevent="apply(text.trim())"
    >
      <Input
        v-model="text"
        size="sm"
        autofocus
        class="flex-1"
        :placeholder="t('CONTACTS_LAYOUT.FILTER.QUICK.COMPANY.PLACEHOLDER')"
      />
      <Button
        type="submit"
        size="sm"
        :label="t('CONTACTS_LAYOUT.FILTER.QUICK.APPLY')"
      />
    </form>
    <QuickFilterOptions
      v-else
      :options="options"
      :selected="selected"
      :search-placeholder="searchPlaceholder"
      :empty-label="
        isLabels ? t('CONTACTS_LAYOUT.FILTER.QUICK.LABELS.EMPTY') : ''
      "
      @select="onSelect"
    />
    <form
      v-if="isLastActivity"
      class="flex flex-col gap-1.5 pt-2 border-t border-n-weak"
      @submit.prevent="apply(customDate)"
    >
      <span class="px-2 text-label-small text-n-slate-11">
        {{ t('CONTACTS_LAYOUT.FILTER.QUICK.LAST_ACTIVITY.CUSTOM_DATE') }}
      </span>
      <div class="flex items-center gap-2">
        <Input v-model="customDate" type="date" size="sm" class="flex-1" />
        <Button
          type="submit"
          size="sm"
          :disabled="!customDate"
          :label="t('CONTACTS_LAYOUT.FILTER.QUICK.APPLY')"
        />
      </div>
    </form>
    <Button
      v-if="isLabels && options.length"
      size="sm"
      :label="t('CONTACTS_LAYOUT.FILTER.QUICK.APPLY')"
      @click="apply(selectedLabels)"
    />
    <Button
      v-if="value !== null"
      variant="ghost"
      color="slate"
      size="xs"
      class="self-start"
      :label="t('CONTACTS_LAYOUT.FILTER.QUICK.CLEAR')"
      @click="emit('clear')"
    />
  </div>
</template>
