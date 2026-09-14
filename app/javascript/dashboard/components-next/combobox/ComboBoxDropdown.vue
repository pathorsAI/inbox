<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  ComboboxAnchor,
  ComboboxContent,
  ComboboxEmpty,
  ComboboxInput,
  ComboboxItem,
  ComboboxItemIndicator,
  ComboboxPortal,
  ComboboxRoot,
  ComboboxViewport,
  ConfigProvider,
} from 'reka-ui';

import { useMapGetter } from 'dashboard/composables/store';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  options: {
    type: Array,
    required: true,
  },
  searchPlaceholder: {
    type: String,
    default: '',
  },
  emptyState: {
    type: String,
    default: '',
  },
  multiple: {
    type: Boolean,
    default: false,
  },
  selectedValues: {
    type: [String, Number, Array],
    default: () => [],
  },
  loading: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['select', 'search']);

const { t } = useI18n();

const open = defineModel('open', {
  type: Boolean,
  default: false,
});

const searchValue = defineModel('searchValue', {
  type: String,
  default: '',
});

const isRTL = useMapGetter('accounts/isRTL');
// reka positions and mirrors `ltr:`/`rtl:` utilities off this, so the portalled
// content keeps the app's reading direction.
const direction = computed(() => (isRTL.value ? 'rtl' : 'ltr'));

// Items carry the whole option, so an option with an empty string value (a
// "None" entry) stays valid; `by` keeps the comparison on `value`.
const selectionModel = computed(() =>
  Array.isArray(props.selectedValues)
    ? props.selectedValues.map(value => ({ value }))
    : { value: props.selectedValues }
);

// reka owns highlight, keyboard and dismissal; selection stays with the caller,
// so cancel the primitive's own model write and hand the option back instead.
const onSelect = (event, option) => {
  event.preventDefault();
  emit('select', option);
};

const onSearchInput = value => {
  searchValue.value = value;
  emit('search', value);
};
</script>

<template>
  <ConfigProvider :dir="direction">
    <ComboboxRoot
      v-model:open="open"
      :model-value="selectionModel"
      :multiple="multiple"
      by="value"
      ignore-filter
      :reset-search-term-on-blur="false"
      :reset-search-term-on-select="false"
      class="w-full min-w-0"
    >
      <ComboboxAnchor as-child>
        <slot />
      </ComboboxAnchor>

      <ComboboxPortal>
        <ComboboxContent
          position="popper"
          :side-offset="4"
          :collision-padding="16"
          class="z-[9999] w-[var(--reka-combobox-trigger-width)] border rounded-md shadow-lg bg-n-solid-1 border-n-strong duration-fast ease-out-soft data-[state=open]:animate-in data-[state=open]:fade-in-0 data-[state=open]:zoom-in-95 data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=closed]:zoom-out-95 motion-reduce:animate-none"
        >
          <div class="relative border-b border-n-strong">
            <Spinner
              v-if="loading"
              :size="16"
              class="absolute top-2.5 start-3 text-n-slate-11"
            />
            <Icon
              v-else
              icon="i-lucide-search"
              class="absolute top-2.5 size-4 start-3"
            />
            <ComboboxInput
              :model-value="searchValue"
              type="search"
              :placeholder="
                searchPlaceholder || t('COMBOBOX.SEARCH_PLACEHOLDER')
              "
              class="reset-base w-full py-2 !ps-10 !pe-2 text-sm focus:outline-none border-none rounded-t-md bg-n-solid-1 text-n-slate-12"
              @update:model-value="onSearchInput"
            />
          </div>
          <ComboboxViewport
            class="py-1 max-h-60"
            :aria-multiselectable="multiple"
          >
            <ComboboxItem
              v-for="(option, index) in options"
              :key="`${option.value}-${index}`"
              :value="option"
              :text-value="option.label"
              class="flex items-center justify-between w-full gap-2 px-3 py-2 text-sm transition-colors duration-150 cursor-pointer group/option focus:outline-none hover:bg-n-alpha-2 data-[highlighted]:bg-n-alpha-2 data-[state=checked]:bg-n-alpha-2"
              @select="onSelect($event, option)"
            >
              <span
                class="text-n-slate-12 group-data-[state=checked]/option:font-medium"
              >
                {{ option.label }}
              </span>
              <ComboboxItemIndicator
                class="flex-shrink-0 i-lucide-check size-4 text-n-slate-11"
              />
            </ComboboxItem>
            <ComboboxEmpty class="px-3 py-2 mb-0 text-sm text-n-slate-11">
              {{ emptyState || t('COMBOBOX.EMPTY_STATE') }}
            </ComboboxEmpty>
          </ComboboxViewport>
        </ComboboxContent>
      </ComboboxPortal>
    </ComboboxRoot>
  </ConfigProvider>
</template>
