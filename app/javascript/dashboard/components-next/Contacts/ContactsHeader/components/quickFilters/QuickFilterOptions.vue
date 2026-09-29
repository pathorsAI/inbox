<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  // [{ value, label }]
  options: { type: Array, required: true },
  selected: { type: Array, default: () => [] },
  searchPlaceholder: { type: String, default: '' },
  emptyLabel: { type: String, default: '' },
});

const emit = defineEmits(['select']);

const { t } = useI18n();
const query = ref('');

const selectedValues = computed(() => new Set(props.selected));

const filteredOptions = computed(() => {
  const term = query.value.trim().toLowerCase();
  if (!term) return props.options;
  return props.options.filter(option =>
    option.label.toLowerCase().includes(term)
  );
});
</script>

<template>
  <div class="flex flex-col gap-1 min-w-0">
    <input
      v-if="searchPlaceholder"
      v-model="query"
      type="search"
      :placeholder="searchPlaceholder"
      class="w-full h-8 px-2 mb-1 text-body-main reset-base rounded-lg outline-none border-none bg-n-alpha-black2 text-n-slate-12 placeholder:text-n-slate-10"
    />
    <div class="flex flex-col overflow-y-auto max-h-60">
      <button
        v-for="option in filteredOptions"
        :key="option.value"
        type="button"
        :aria-pressed="selectedValues.has(option.value)"
        class="flex items-center justify-between flex-shrink-0 gap-2 h-8 px-2 rounded-md text-body-main text-start text-n-slate-12 hover:bg-n-alpha-2"
        @click="emit('select', option.value)"
      >
        <span class="truncate">{{ option.label }}</span>
        <Icon
          v-if="selectedValues.has(option.value)"
          icon="i-lucide-check"
          class="size-4 shrink-0 text-n-blue-11"
        />
      </button>
      <p
        v-if="!filteredOptions.length"
        class="px-2 py-1.5 mb-0 text-label-small text-n-slate-11"
      >
        {{ query ? t('CONTACTS_LAYOUT.FILTER.QUICK.NO_MATCHES') : emptyLabel }}
      </p>
    </div>
  </div>
</template>
