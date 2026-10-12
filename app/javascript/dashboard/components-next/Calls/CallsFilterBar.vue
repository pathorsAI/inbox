<script setup>
import { computed, ref } from 'vue';
import { OnClickOutside } from '@vueuse/components';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import { CALL_OUTCOMES } from 'dashboard/helper/pathorsCallState';
import { CALL_DATE_RANGES, CALL_SEGMENTS } from './constants';

const props = defineProps({
  // The need/live views are a segment themselves, so they hide the control.
  showSegments: { type: Boolean, default: true },
  // `meta.counts` of the last list response: { need, live }.
  counts: { type: Object, default: () => ({}) },
  // The line filter; empty (the line view) hides it.
  inboxes: { type: Array, default: () => [] },
});

const search = defineModel('search', { type: String, default: '' });
const segment = defineModel('segment', { type: String, default: null });
const dateRange = defineModel('dateRange', { type: String, default: null });
const outcome = defineModel('outcome', { type: String, default: null });
const inboxId = defineModel('inboxId', { type: Number, default: null });

const { t } = useI18n();

// "Asked for help" filters alongside the outcomes, whatever came of it.
const OUTCOME_FILTERS = [...CALL_OUTCOMES, 'takeover_requested'];

// One open menu at a time; each wrapper closes only its own menu on an
// outside click, so the click that opens another one is not swallowed.
const openMenu = ref(null);
const toggleMenu = name => {
  openMenu.value = openMenu.value === name ? null : name;
};
const closeOnOutside = name => {
  if (openMenu.value === name) openMenu.value = null;
};

const segmentTabs = computed(() => [
  {
    label: t('CALLS_PAGE.SEGMENTS.NEED'),
    count: props.counts.need || 0,
    value: CALL_SEGMENTS.NEED,
  },
  {
    label: t('CALLS_PAGE.SEGMENTS.LIVE'),
    count: props.counts.live || 0,
    value: CALL_SEGMENTS.LIVE,
  },
  { label: t('CALLS_PAGE.SEGMENTS.ENDED'), value: CALL_SEGMENTS.ENDED },
  { label: t('CALLS_PAGE.SEGMENTS.ALL'), value: null },
]);

const activeSegmentIndex = computed(() =>
  segmentTabs.value.findIndex(tab => tab.value === segment.value)
);

const dateLabel = value =>
  value
    ? t(`CALLS_PAGE.FILTERS.DATE_${value.toUpperCase()}`)
    : t('CALLS_PAGE.FILTERS.DATE_ANY');

const outcomeLabel = value =>
  value
    ? t(`CALLS_PAGE.OUTCOME.${value.toUpperCase()}`)
    : t('CALLS_PAGE.FILTERS.OUTCOME_ANY');

const dateItems = computed(() =>
  [null, ...CALL_DATE_RANGES].map(value => ({
    label: dateLabel(value),
    value,
    action: 'date',
    isSelected: dateRange.value === value,
  }))
);

const outcomeItems = computed(() =>
  [null, ...OUTCOME_FILTERS].map(value => ({
    label: outcomeLabel(value),
    value,
    action: 'outcome',
    isSelected: outcome.value === value,
  }))
);

const lineItems = computed(() => [
  {
    label: t('CALLS_PAGE.FILTERS.LINE_ANY'),
    value: null,
    action: 'line',
    isSelected: !inboxId.value,
  },
  ...props.inboxes.map(inbox => ({
    label: inbox.name,
    value: inbox.id,
    action: 'line',
    isSelected: inboxId.value === inbox.id,
  })),
]);

const selectedLineLabel = computed(
  () =>
    props.inboxes.find(inbox => inbox.id === inboxId.value)?.name ||
    t('CALLS_PAGE.FILTERS.LINE_ANY')
);

const menus = computed(() => [
  {
    name: 'date',
    icon: 'i-lucide-calendar',
    label: dateLabel(dateRange.value),
    isActive: !!dateRange.value,
    items: dateItems.value,
  },
  {
    name: 'outcome',
    icon: 'i-lucide-list-filter',
    label: outcomeLabel(outcome.value),
    isActive: !!outcome.value,
    items: outcomeItems.value,
  },
  ...(props.inboxes.length
    ? [
        {
          name: 'line',
          icon: 'i-lucide-phone',
          label: selectedLineLabel.value,
          isActive: !!inboxId.value,
          items: lineItems.value,
        },
      ]
    : []),
]);

const MODEL_BY_ACTION = { date: dateRange, outcome, line: inboxId };

const onMenuAction = ({ action, value }) => {
  openMenu.value = null;
  MODEL_BY_ACTION[action].value = value;
};
</script>

<template>
  <div class="flex flex-wrap items-center gap-3">
    <Input
      v-model="search"
      type="search"
      size="sm"
      class="w-full sm:w-64"
      :placeholder="t('CALLS_PAGE.FILTERS.SEARCH_PLACEHOLDER')"
    />
    <TabBar
      v-if="showSegments"
      :tabs="segmentTabs"
      :initial-active-tab="activeSegmentIndex"
      @tab-changed="segment = $event.value"
    />
    <div class="flex flex-wrap items-center gap-2">
      <OnClickOutside
        v-for="menu in menus"
        :key="menu.name"
        class="relative shrink-0"
        @trigger="closeOnOutside(menu.name)"
      >
        <Button
          variant="outline"
          size="sm"
          :icon="menu.icon"
          class="max-w-56 !h-7 !px-2"
          :color="menu.isActive ? 'blue' : 'slate'"
          :class="menu.isActive ? '' : 'text-n-slate-11'"
          @click="toggleMenu(menu.name)"
        >
          <span class="truncate">{{ menu.label }}</span>
          <Icon icon="i-lucide-chevron-down" class="shrink-0" />
        </Button>
        <DropdownMenu
          v-if="openMenu === menu.name"
          :menu-items="menu.items"
          class="mt-1 start-0 top-full w-48 max-h-80"
          @action="onMenuAction"
        />
      </OnClickOutside>
    </div>
  </div>
</template>
