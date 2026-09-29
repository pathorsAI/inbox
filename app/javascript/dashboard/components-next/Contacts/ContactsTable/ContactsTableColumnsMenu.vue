<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Popover from 'dashboard/components-next/popover/Popover.vue';

defineProps({
  // Contact custom attribute definitions (camelCased).
  definitions: { type: Array, default: () => [] },
});

// The attribute keys shown as extra columns, in the order they were added.
const selectedKeys = defineModel({ type: Array, default: () => [] });

const { t } = useI18n();

const toggle = key => {
  selectedKeys.value = selectedKeys.value.includes(key)
    ? selectedKeys.value.filter(selected => selected !== key)
    : [...selectedKeys.value, key];
};
</script>

<template>
  <Popover align="end">
    <Button
      icon="i-lucide-columns-3"
      variant="ghost"
      color="slate"
      size="xs"
      :label="t('CONTACTS_LAYOUT.TABLE.COLUMNS_MENU.LABEL')"
    />
    <template #content>
      <div class="flex flex-col w-64 p-1">
        <span class="px-2 pt-1 pb-2 text-label-small text-n-slate-11">
          {{ t('CONTACTS_LAYOUT.TABLE.COLUMNS_MENU.TITLE') }}
        </span>
        <label
          v-for="definition in definitions"
          :key="definition.attributeKey"
          class="flex items-center gap-2 h-8 px-2 rounded-md cursor-pointer text-body-main text-n-slate-12 hover:bg-n-alpha-2"
        >
          <Checkbox
            :model-value="selectedKeys.includes(definition.attributeKey)"
            @change="toggle(definition.attributeKey)"
          />
          <span class="truncate">{{ definition.attributeDisplayName }}</span>
        </label>
        <span
          v-if="!definitions.length"
          class="px-2 pb-2 text-body-main text-n-slate-11"
        >
          {{ t('CONTACTS_LAYOUT.TABLE.COLUMNS_MENU.EMPTY') }}
        </span>
      </div>
    </template>
  </Popover>
</template>
