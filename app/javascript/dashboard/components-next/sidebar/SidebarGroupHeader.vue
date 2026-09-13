<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store.js';
import Icon from 'next/icon/Icon.vue';
import SidebarUnreadBadge from './SidebarUnreadBadge.vue';

const props = defineProps({
  to: { type: [Object, String], default: '' },
  label: { type: String, default: '' },
  icon: { type: [String, Object], default: '' },
  expandable: { type: Boolean, default: false },
  isExpanded: { type: Boolean, default: false },
  isActive: { type: Boolean, default: false },
  hasActiveChild: { type: Boolean, default: false },
  getterKeys: { type: Object, default: () => ({}) },
  badgeCount: { type: [Number, String], default: 0 },
  badgeTone: { type: String, default: 'neutral' },
  badgeTitle: { type: String, default: '' },
  badgeTo: { type: [Object, String], default: null },
});

const emit = defineEmits(['toggle', 'activate']);

const { t } = useI18n();

const showBadge = useMapGetter(props.getterKeys.badge);
const dynamicCount = useMapGetter(props.getterKeys.count);
// An expandable group used to have no room for a number because its children
// carry them. `badgeCount` is the exception: a group-level signal that has to
// stay visible while the group is folded away.
const count = computed(() =>
  props.expandable ? props.badgeCount : dynamicCount.value
);
</script>

<template>
  <component
    :is="to ? 'router-link' : 'div'"
    class="flex items-center gap-2 px-1.5 py-1 rounded-lg h-8 min-w-0"
    role="button"
    draggable="false"
    :to="to"
    :title="label"
    :class="{
      'text-n-slate-12 bg-n-alpha-2 font-medium': isActive && !hasActiveChild,
      'text-n-slate-12 font-medium': hasActiveChild,
      'text-n-slate-11 hover:bg-n-alpha-2': !isActive && !hasActiveChild,
    }"
    @click.stop="emit('activate')"
  >
    <div v-if="icon" class="relative flex items-center gap-2">
      <Icon v-if="icon" :icon="icon" class="size-4" />
      <span
        v-if="showBadge"
        class="size-2 -top-px ltr:-right-px rtl:-left-px bg-n-brand absolute rounded-full border border-n-solid-2"
      />
    </div>
    <div
      class="flex items-center gap-1.5 flex-grow justify-between min-w-0 flex-1"
    >
      <span
        class="truncate"
        :class="{
          'text-body-main': !isActive,
          'font-medium text-sm': isActive || hasActiveChild,
        }"
      >
        {{ label }}
      </span>
      <component
        :is="badgeTo ? 'router-link' : 'span'"
        v-if="count"
        :to="badgeTo"
        class="flex-shrink-0"
        @click.stop
      >
        <SidebarUnreadBadge
          :count="count"
          :tone="badgeTone"
          :title="badgeTitle"
        />
      </component>
    </div>
    <button
      v-if="expandable"
      type="button"
      class="grid flex-shrink-0 place-content-center rounded size-4 text-n-slate-11 hover:bg-n-alpha-2 disabled:hover:bg-transparent disabled:cursor-default"
      :disabled="hasActiveChild"
      :aria-expanded="isExpanded"
      :aria-label="t('SIDEBAR.TOGGLE_GROUP', { label })"
      @click.stop.prevent="emit('toggle')"
    >
      <span
        class="i-lucide-chevron-down size-3 transition-transform duration-200 motion-reduce:transition-none"
        :class="{ 'rotate-180': isExpanded }"
      />
    </button>
  </component>
</template>
