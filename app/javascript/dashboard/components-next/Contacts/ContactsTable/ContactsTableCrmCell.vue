<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import LabelChip from 'dashboard/components-next/label/Label.vue';
import { CRM_ATTRIBUTE, crmStatusOf } from '../crmAttributes';
import { isWebUrl } from './contactsTable';

const props = defineProps({
  // The contact's custom attributes (raw crm_* keys).
  attributes: { type: Object, default: () => ({}) },
  // The account's crm_status definition (camelCased).
  statusDefinition: { type: Object, required: true },
});

const { t } = useI18n();

const STATUS_DOT_CLASSES = {
  linked: 'bg-n-teal-9',
  needs_attention: 'bg-n-amber-9',
};

const attribute = key => props.attributes?.[key];

const statusValue = computed(() => attribute(CRM_ATTRIBUTE.STATUS));
const status = computed(() =>
  crmStatusOf(props.statusDefinition, statusValue.value)
);
const dotClass = computed(() => STATUS_DOT_CLASSES[status.value]);
const stage = computed(() => attribute(CRM_ATTRIBUTE.STAGE));
const url = computed(() => {
  const value = attribute(CRM_ATTRIBUTE.URL);
  return isWebUrl(value) ? value : null;
});

const tooltip = computed(() => {
  const opportunity = attribute(CRM_ATTRIBUTE.OPPORTUNITY);
  const owner = attribute(CRM_ATTRIBUTE.OWNER);
  const parts = [
    statusValue.value,
    attribute(CRM_ATTRIBUTE.PROVIDER),
    opportunity &&
      t('CONTACTS_LAYOUT.TABLE.CRM.OPPORTUNITY', { name: opportunity }),
    owner && t('CONTACTS_LAYOUT.TABLE.CRM.OWNER', { name: owner }),
  ].filter(Boolean);
  return parts.length ? parts.join(' · ') : null;
});
</script>

<template>
  <component
    :is="url ? 'a' : 'div'"
    v-tooltip.top="tooltip"
    :href="url"
    :target="url ? '_blank' : undefined"
    :rel="url ? 'noopener noreferrer' : undefined"
    data-test="crm-cell"
    class="flex items-center gap-1.5 h-9 px-3 min-w-0"
    @click="url && $event.stopPropagation()"
  >
    <span
      v-if="dotClass"
      data-test="crm-status-dot"
      :data-status="status"
      class="size-2 rounded-full shrink-0"
      :class="dotClass"
    />
    <LabelChip v-if="stage" compact :label="stage" />
    <span v-if="!dotClass && !stage" class="text-n-slate-10">
      {{ t('CONTACTS_LAYOUT.TABLE.EMPTY_CELL') }}
    </span>
  </component>
</template>
