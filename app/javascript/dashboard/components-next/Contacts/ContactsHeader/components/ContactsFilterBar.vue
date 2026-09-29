<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  breakpointsTailwind,
  useBreakpoints,
  useResizeObserver,
} from '@vueuse/core';
import countries from 'shared/constants/countries';
import { TWENTY_STATUSES } from 'dashboard/routes/dashboard/contacts/contactFilterItems';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import QuickFilterPill from './quickFilters/QuickFilterPill.vue';
import QuickFilterEditor from './quickFilters/QuickFilterEditor.vue';
import {
  CONTACT_METHOD,
  LAST_ACTIVITY_PRESETS,
  QUICK_FILTER,
  QUICK_FILTER_ORDER,
  clearQuickFilter,
  hasOrJoin,
  lastActivityPreset,
  readQuickFilters,
  setQuickFilter,
} from './quickFilters/conditions';
import { fitPillCount } from './quickFilters/layout';

const props = defineProps({
  // Applied conditions, camelCased (contacts/getAppliedContactFiltersV4).
  filters: { type: Array, default: () => [] },
  labels: { type: Array, default: () => [] },
  showTwenty: { type: Boolean, default: false },
});

// `apply` carries the whole new condition list; an empty list means nothing is left applied.
const emit = defineEmits([
  'apply',
  'openAdvanced',
  'createSegment',
  'clearAll',
]);

const { t } = useI18n();
const quickT = (key, params) =>
  t(`CONTACTS_LAYOUT.FILTER.QUICK.${key}`, params);

const pillKeys = computed(() =>
  props.showTwenty
    ? QUICK_FILTER_ORDER
    : QUICK_FILTER_ORDER.filter(key => key !== QUICK_FILTER.TWENTY_STATUS)
);
const quickFilters = computed(() =>
  readQuickFilters(props.filters, pillKeys.value)
);
const isLocked = computed(() => hasOrJoin(props.filters));

const OPTIONS = {
  [QUICK_FILTER.LAST_ACTIVITY]: () =>
    LAST_ACTIVITY_PRESETS.map(({ key, days }) => ({
      value: days,
      label: quickT(`LAST_ACTIVITY.${key}`),
    })),
  [QUICK_FILTER.LABELS]: () =>
    props.labels.map(({ title }) => ({ value: title, label: title })),
  [QUICK_FILTER.COMPANY]: () => [],
  [QUICK_FILTER.COUNTRY]: () =>
    countries.map(({ id, name }) => ({ value: id, label: name })),
  [QUICK_FILTER.CONTACT_METHOD]: () =>
    Object.values(CONTACT_METHOD).map(method => ({
      value: method,
      label: quickT(`CONTACT_METHOD.${method}`),
    })),
  [QUICK_FILTER.TWENTY_STATUS]: () =>
    TWENTY_STATUSES.map(status => ({
      value: status,
      label: quickT(`TWENTY_STATUS.${status.toUpperCase()}`),
    })),
};

const valueLabel = (key, value, options) => {
  if (key === QUICK_FILTER.LABELS) return value.join(', ');
  if (key === QUICK_FILTER.LAST_ACTIVITY) {
    const preset = lastActivityPreset(value);
    return preset
      ? quickT(`LAST_ACTIVITY.${preset.key}`)
      : quickT('LAST_ACTIVITY.AFTER', { date: value });
  }
  return options.find(option => option.value === value)?.label ?? value;
};

const pills = computed(() =>
  pillKeys.value.map(key => {
    const value = quickFilters.value.values[key];
    const options = OPTIONS[key]();
    const name = quickT(`${key}.LABEL`);
    return {
      key,
      value,
      options,
      isSet: value !== null,
      count: quickFilters.value.counts[key],
      text:
        value === null
          ? name
          : quickT('PILL_VALUE', {
              label: name,
              value: valueLabel(key, value, options),
            }),
    };
  })
);

const barRef = ref(null);
const probeRef = ref(null);
const actionsRef = ref(null);
const measured = ref(null);
const isBelowSm = useBreakpoints(breakpointsTailwind).smaller('sm');

const gapOf = element => parseFloat(getComputedStyle(element).columnGap) || 0;

const measure = () => {
  const [overflowWidth, advancedWidth, ...pillWidths] = [
    ...probeRef.value.children,
  ].map(element => element.offsetWidth);
  measured.value = {
    barWidth: barRef.value.clientWidth,
    pillWidths,
    overflowWidth,
    advancedWidth,
    actionsWidth: actionsRef.value?.offsetWidth ?? 0,
    gap: gapOf(probeRef.value),
    actionsGap: gapOf(barRef.value),
  };
};

useResizeObserver([barRef, probeRef, actionsRef], measure);

const visibleCount = computed(() => {
  if (isBelowSm.value) return 0;
  return measured.value ? fitPillCount(measured.value) : pills.value.length;
});
const visiblePills = computed(() => pills.value.slice(0, visibleCount.value));
const collapsedPills = computed(() => pills.value.slice(visibleCount.value));
const collapsedCount = computed(() =>
  collapsedPills.value.reduce((sum, pill) => sum + pill.count, 0)
);

const overflowLabel = computed(() =>
  collapsedCount.value
    ? quickT('MORE_COUNT', { count: collapsedCount.value })
    : quickT('MORE')
);
const advancedLabel = computed(() => {
  const count = quickFilters.value.advancedCount;
  return count ? quickT('ADVANCED_COUNT', { count }) : quickT('ADVANCED');
});

const expandedPill = ref(null);
const toggleExpanded = key => {
  expandedPill.value = expandedPill.value === key ? null : key;
};

// A null value clears the pill.
const update = (key, value) => {
  if (value !== null) {
    emit('apply', setQuickFilter(props.filters, key, value));
  } else if (quickFilters.value.counts[key]) {
    emit('apply', clearQuickFilter(props.filters, key));
  }
};

const updateAndClose = (key, value, hide) => {
  update(key, value);
  hide();
};
</script>

<template>
  <div
    ref="barRef"
    class="relative flex flex-wrap items-center gap-x-4 gap-y-2 min-w-0"
  >
    <!-- An invisible copy of the bar's buttons, measured to decide how many pills fit. -->
    <div
      aria-hidden="true"
      class="absolute inset-x-0 top-0 h-0 overflow-hidden invisible"
    >
      <div ref="probeRef" class="flex gap-2 w-max">
        <QuickFilterPill
          icon="i-lucide-list-filter"
          :label="overflowLabel"
          :active="collapsedCount > 0"
        />
        <QuickFilterPill
          icon="i-lucide-plus"
          :label="advancedLabel"
          :active="quickFilters.advancedCount > 0"
        />
        <QuickFilterPill
          v-for="pill in pills"
          :key="pill.key"
          :label="pill.text"
          :active="pill.isSet"
          :clearable="pill.isSet"
        />
      </div>
    </div>

    <div class="flex items-center min-w-0 gap-2">
      <template v-for="pill in visiblePills" :key="pill.key">
        <QuickFilterPill
          v-if="isLocked"
          v-tooltip.top="quickT('OR_LOCKED')"
          :label="pill.text"
          :active="pill.isSet"
          :clearable="pill.isSet"
          disabled
        />
        <Popover v-else align="start">
          <QuickFilterPill
            :label="pill.text"
            :active="pill.isSet"
            :clearable="pill.isSet"
            @clear="update(pill.key, null)"
          />
          <template #content="{ hide }">
            <QuickFilterEditor
              class="w-64 p-3"
              :pill="pill.key"
              :value="pill.value"
              :options="pill.options"
              @apply="value => updateAndClose(pill.key, value, hide)"
              @clear="updateAndClose(pill.key, null, hide)"
            />
          </template>
        </Popover>
      </template>

      <template v-if="collapsedPills.length">
        <QuickFilterPill
          v-if="isLocked"
          v-tooltip.top="quickT('OR_LOCKED')"
          icon="i-lucide-list-filter"
          :label="overflowLabel"
          :active="collapsedCount > 0"
          disabled
        />
        <Popover v-else align="start" @hide="expandedPill = null">
          <QuickFilterPill
            icon="i-lucide-list-filter"
            :label="overflowLabel"
            :active="collapsedCount > 0"
          />
          <template #content="{ hide }">
            <div class="flex flex-col w-72 p-1">
              <div
                v-for="pill in collapsedPills"
                :key="pill.key"
                class="flex flex-col"
              >
                <button
                  type="button"
                  class="flex items-center justify-between gap-2 h-8 px-2 rounded-md text-body-main text-start hover:bg-n-alpha-2"
                  :class="pill.isSet ? 'text-n-blue-11' : 'text-n-slate-12'"
                  :aria-expanded="expandedPill === pill.key"
                  @click="toggleExpanded(pill.key)"
                >
                  <span class="truncate">{{ pill.text }}</span>
                  <Icon
                    :icon="
                      expandedPill === pill.key
                        ? 'i-lucide-chevron-up'
                        : 'i-lucide-chevron-down'
                    "
                    class="size-4 shrink-0 text-n-slate-11"
                  />
                </button>
                <QuickFilterEditor
                  v-if="expandedPill === pill.key"
                  class="px-2 pt-1 pb-3"
                  :pill="pill.key"
                  :value="pill.value"
                  :options="pill.options"
                  @apply="value => updateAndClose(pill.key, value, hide)"
                  @clear="updateAndClose(pill.key, null, hide)"
                />
              </div>
            </div>
          </template>
        </Popover>
      </template>

      <Popover align="start" @show="emit('openAdvanced')">
        <QuickFilterPill
          icon="i-lucide-plus"
          :label="advancedLabel"
          :active="quickFilters.advancedCount > 0"
        />
        <template #content="{ hide }">
          <slot name="advanced" :hide="hide" />
        </template>
      </Popover>
    </div>

    <div
      v-if="filters.length"
      ref="actionsRef"
      class="flex items-center gap-1 ms-auto shrink-0"
    >
      <Button
        variant="ghost"
        color="slate"
        size="xs"
        :label="quickT('SAVE_SEGMENT')"
        @click="emit('createSegment')"
      />
      <Button
        variant="ghost"
        color="slate"
        size="xs"
        :label="quickT('CLEAR_ALL')"
        @click="emit('clearAll')"
      />
    </div>
  </div>
</template>
