<script setup>
import { computed, toRef } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import SelectMenu from 'dashboard/components-next/selectmenu/SelectMenu.vue';

const props = defineProps({
  activeSort: {
    type: String,
    default: 'name',
  },
  activeOrdering: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['update:sort']);

const { t } = useI18n();

const sortMenus = [
  {
    label: t('COMPANIES.SORT_BY.OPTIONS.NAME'),
    value: 'name',
  },
  {
    label: t('COMPANIES.SORT_BY.OPTIONS.DOMAIN'),
    value: 'domain',
  },
  {
    label: t('COMPANIES.SORT_BY.OPTIONS.CREATED_AT'),
    value: 'created_at',
  },
  {
    label: t('COMPANIES.SORT_BY.OPTIONS.LAST_ACTIVITY_AT'),
    value: 'last_activity_at',
  },
  {
    label: t('COMPANIES.SORT_BY.OPTIONS.CONTACTS_COUNT'),
    value: 'contacts_count',
  },
];

const orderingMenus = [
  {
    label: t('COMPANIES.ORDER.OPTIONS.ASCENDING'),
    value: '',
  },
  {
    label: t('COMPANIES.ORDER.OPTIONS.DESCENDING'),
    value: '-',
  },
];

// Converted the props to refs for better reactivity
const activeSort = toRef(props, 'activeSort');

const activeOrdering = toRef(props, 'activeOrdering');

const activeSortLabel = computed(() => {
  const selectedMenu = sortMenus.find(menu => menu.value === activeSort.value);
  return selectedMenu?.label || t('COMPANIES.SORT_BY.LABEL');
});

const activeOrderingLabel = computed(() => {
  const selectedMenu = orderingMenus.find(
    menu => menu.value === activeOrdering.value
  );
  return selectedMenu?.label || t('COMPANIES.ORDER.LABEL');
});

const handleSortChange = value => {
  emit('update:sort', { sort: value, order: props.activeOrdering });
};

const handleOrderChange = value => {
  emit('update:sort', { sort: props.activeSort, order: value });
};
</script>

<template>
  <Popover disable-mobile-view :show-content-border="false">
    <template #default="{ isOpen }">
      <Button
        icon="i-lucide-arrow-down-up"
        color="slate"
        size="sm"
        variant="ghost"
        :class="isOpen ? 'bg-n-alpha-2' : ''"
      />
    </template>
    <template #content>
      <div class="flex flex-col gap-4 border border-n-weak w-72 rounded-xl p-4">
        <div class="flex items-center justify-between gap-2">
          <span class="text-sm text-n-slate-12">
            {{ t('COMPANIES.SORT_BY.LABEL') }}
          </span>
          <SelectMenu
            :model-value="activeSort"
            :options="sortMenus"
            :label="activeSortLabel"
            @update:model-value="handleSortChange"
          />
        </div>
        <div class="flex items-center justify-between gap-2">
          <span class="text-sm text-n-slate-12">
            {{ t('COMPANIES.ORDER.LABEL') }}
          </span>
          <SelectMenu
            :model-value="activeOrdering"
            :options="orderingMenus"
            :label="activeOrderingLabel"
            @update:model-value="handleOrderChange"
          />
        </div>
      </div>
    </template>
  </Popover>
</template>
