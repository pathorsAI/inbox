<script setup>
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';

defineProps({
  label: { type: String, required: true },
  // Leading icon for the bar's own buttons; filter pills show a chevron instead.
  icon: { type: String, default: '' },
  active: { type: Boolean, default: false },
  clearable: { type: Boolean, default: false },
  disabled: { type: Boolean, default: false },
});

const emit = defineEmits(['clear']);

const { t } = useI18n();
</script>

<template>
  <div
    class="inline-flex items-center h-7 max-w-60 min-w-0 shrink-0 rounded-lg text-button-small outline outline-1 -outline-offset-1 transition-colors"
    :class="[
      active
        ? 'bg-n-brand/10 text-n-blue-11 outline-transparent'
        : 'text-n-slate-11 outline-n-weak',
      { 'opacity-50': disabled },
    ]"
  >
    <button
      type="button"
      :disabled="disabled"
      :title="label"
      class="flex items-center min-w-0 h-full gap-1 px-2.5 rounded-lg enabled:hover:bg-n-alpha-2 disabled:pointer-events-none"
      :class="{ 'pe-1': clearable }"
    >
      <Icon v-if="icon" :icon="icon" class="size-3.5 shrink-0" />
      <span class="truncate">{{ label }}</span>
      <Icon
        v-if="!icon && !clearable"
        icon="i-lucide-chevron-down"
        class="size-3.5 shrink-0"
      />
    </button>
    <button
      v-if="clearable"
      type="button"
      :disabled="disabled"
      :aria-label="t('CONTACTS_LAYOUT.FILTER.QUICK.CLEAR_PILL', { label })"
      class="flex items-center justify-center h-full px-1.5 rounded-lg enabled:hover:bg-n-alpha-2 disabled:pointer-events-none"
      @click.stop="emit('clear')"
    >
      <Icon icon="i-lucide-x" class="size-3.5" />
    </button>
  </div>
</template>
