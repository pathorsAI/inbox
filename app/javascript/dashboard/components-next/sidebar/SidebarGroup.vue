<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { useSidebarContext, usePopoverState } from './provider';
import { useRoute, useRouter } from 'vue-router';
import Policy from 'dashboard/components/policy.vue';
import Icon from 'next/icon/Icon.vue';
import SidebarGroupHeader from './SidebarGroupHeader.vue';
import SidebarGroupLeaf from './SidebarGroupLeaf.vue';
import SidebarSubGroup from './SidebarSubGroup.vue';
import SidebarGroupEmptyLeaf from './SidebarGroupEmptyLeaf.vue';
import SidebarCollapsedPopover from './SidebarCollapsedPopover.vue';
import SidebarUnreadBadge from './SidebarUnreadBadge.vue';

const props = defineProps({
  name: { type: String, required: true },
  label: { type: String, required: true },
  icon: { type: [String, Object, Function], default: null },
  to: { type: Object, default: null },
  activeOn: { type: Array, default: () => [] },
  children: { type: Array, default: undefined },
  getterKeys: { type: Object, default: () => ({}) },
  badgeCount: { type: [Number, String], default: 0 },
  badgeTone: { type: String, default: 'neutral' },
  badgeTitle: { type: String, default: '' },
  badgeTo: { type: Object, default: null },
});

const {
  isItemExpanded,
  toggleExpandedItem,
  expandItem,
  resolvePath,
  resolvePermissions,
  resolveFeatureFlag,
  isAllowed,
  isCollapsed,
  isResizing,
} = useSidebarContext();

const {
  activePopover,
  setActivePopover,
  closeActivePopover,
  scheduleClose,
  cancelClose,
} = usePopoverState();

const navigableChildren = computed(() => {
  return props.children?.flatMap(child => child.children || child) || [];
});

const route = useRoute();
const router = useRouter();
const isExpanded = computed(() => isItemExpanded(props.name));
const isExpandable = computed(() => props.children);
const hasChildren = computed(
  () => Array.isArray(props.children) && props.children.length > 0
);

// Use shared popover state - only one popover can be open at a time
const isPopoverOpen = computed(() => activePopover.value === props.name);
const triggerRef = ref(null);
const triggerRect = ref({ top: 0, left: 0, bottom: 0, right: 0 });
// The sort dropdown teleports outside the popover; keep the popover open while
// it is showing so moving the cursor onto it does not close everything.
const isSortMenuOpen = ref(false);

const openPopover = () => {
  if (triggerRef.value) {
    const rect = triggerRef.value.getBoundingClientRect();
    triggerRect.value = {
      top: rect.top,
      left: rect.left,
      bottom: rect.bottom,
      right: rect.right,
    };
  }
  setActivePopover(props.name);
};

const closePopover = () => {
  if (activePopover.value === props.name) {
    closeActivePopover();
  }
};

const handleMouseEnter = () => {
  if (!hasChildren.value || isResizing.value) return;
  cancelClose();
  openPopover();
};

const handleMouseLeave = () => {
  if (!hasChildren.value || isSortMenuOpen.value) return;
  scheduleClose(200);
};

const handlePopoverMouseEnter = () => {
  cancelClose();
};

const handlePopoverMouseLeave = () => {
  if (isSortMenuOpen.value) return;
  scheduleClose(100);
};

const handleSortToggle = isOpen => {
  isSortMenuOpen.value = isOpen;
  cancelClose();
};

// Close popover when mouse leaves the window
const handleWindowBlur = () => {
  closeActivePopover();
};

const hasAccessibleSubChildren = child => {
  return child.children?.some(
    subChild => subChild.to && isAllowed(subChild.to)
  );
};

const visibleChildren = computed(() => {
  if (!hasChildren.value) return [];

  return props.children.filter(child => {
    if (child.children) return hasAccessibleSubChildren(child);

    return child.to && isAllowed(child.to);
  });
});

const accessibleItems = computed(() => {
  if (!hasChildren.value) return [];

  return visibleChildren.value
    .flatMap(child => child.children || child)
    .filter(child => child.to && isAllowed(child.to));
});

const hasAccessibleChildren = computed(() => {
  return visibleChildren.value.length > 0;
});

const isLastVisibleChild = child => {
  const lastChild = visibleChildren.value[visibleChildren.value.length - 1];
  return lastChild === child;
};

// Folded — to an icon, or just with its children hidden — there is nowhere to
// put per-child numbers, so the group carries what its children were
// signalling: its own badge, or the sum of the children asking for action.
const rolledUpBadgeCount = computed(() => {
  if (props.badgeCount) return Number(props.badgeCount);

  return (props.children || [])
    .filter(
      child => child.badgeTone === 'attention' || child.badgeTone === 'danger'
    )
    .reduce((total, child) => total + Number(child.badgeCount || 0), 0);
});

const rolledUpBadgeTone = computed(() =>
  props.badgeCount ? props.badgeTone : 'attention'
);

const isActive = computed(() => {
  if (props.to) {
    if (route.path === resolvePath(props.to)) return true;

    return props.activeOn.includes(route.name);
  }

  return false;
});

// We could use the RouterLink isActive too, but our routes are not always
// nested correctly, so we need to check the active state ourselves
// TODO: Audit the routes and fix the nesting and remove this
const activeChild = computed(() => {
  const pathSame = navigableChildren.value.find(
    child => child.to && route.path === resolvePath(child.to)
  );
  if (pathSame) return pathSame;

  // Rank the activeOn Prop higher than the path match
  // There will be cases where the path name is the same but the params are different
  // So we need to rank them based on the params
  // For example, contacts segment list in the sidebar effectively has the same name
  // But the params are different
  const activeOnPages = navigableChildren.value.filter(child =>
    child.activeOn?.includes(route.name)
  );

  if (activeOnPages.length > 0) {
    const rankedPage = activeOnPages.find(child => {
      return Object.keys(child.to.params)
        .map(key => {
          return String(child.to.params[key]) === String(route.params[key]);
        })
        .every(match => match);
    });

    // If there is no ranked page, return the first activeOn page anyway
    // Since this takes higher precedence over the path match
    // This is not perfect, ideally we should rank each route based on all the techniques
    // and then return the highest ranked one
    // But this is good enough for now
    return rankedPage ?? activeOnPages[0];
  }

  return navigableChildren.value.find(child => {
    if (!child.to) return false;
    const childPath = resolvePath(child.to);
    return route.path === childPath || route.path.startsWith(`${childPath}/`);
  });
});

const hasActiveChild = computed(() => {
  return activeChild.value !== undefined;
});

// The group holding the active route always shows its children, whether or not
// the agent opened it. Everything that renders the open state reads this rather
// than `isExpanded`, so navigating never has to write to the stored set.
const isOpen = computed(() => isExpanded.value || hasActiveChild.value);

const areChildrenVisible = computed(() => !hasChildren.value || isOpen.value);

const handleCollapsedClick = () => {
  if (hasChildren.value && hasAccessibleChildren.value) {
    const firstItem = accessibleItems.value[0];
    router.push(firstItem.to);
  }
};

// The chevron folds the group and nothing else — no navigation, so an agent can
// peek into a group without leaving the page they are on.
const toggleTrigger = () => {
  toggleExpandedItem(props.name);
};

// The name is what navigates: to the group's own page when it has one, else to
// its first child. Either way the group ends up open.
const handleActivate = () => {
  if (!props.to && hasAccessibleChildren.value) {
    router.push(accessibleItems.value[0].to);
  }

  if (hasChildren.value) expandItem(props.name);
};

onMounted(() => {
  window.addEventListener('blur', handleWindowBlur);
  document.addEventListener('mouseleave', handleWindowBlur);
});

onUnmounted(() => {
  window.removeEventListener('blur', handleWindowBlur);
  document.removeEventListener('mouseleave', handleWindowBlur);
});
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <Policy
    v-if="!hasChildren || hasAccessibleChildren"
    :permissions="resolvePermissions(to)"
    :feature-flag="resolveFeatureFlag(to)"
    as="li"
    class="grid gap-1 text-sm cursor-pointer select-none min-w-0"
  >
    <!-- Collapsed State -->
    <template v-if="isCollapsed">
      <div
        class="relative"
        @mouseenter="handleMouseEnter"
        @mouseleave="handleMouseLeave"
      >
        <component
          :is="to && !hasChildren ? 'router-link' : 'button'"
          ref="triggerRef"
          :to="to && !hasChildren ? to : undefined"
          type="button"
          class="flex items-center justify-center size-10 rounded-lg"
          :class="{
            'text-n-slate-12 bg-n-alpha-2': isActive || hasActiveChild,
            'text-n-slate-11 hover:bg-n-alpha-2': !isActive && !hasActiveChild,
          }"
          :title="label"
          @click="hasChildren ? handleCollapsedClick() : undefined"
        >
          <Icon v-if="icon" :icon="icon" class="size-4" />
          <SidebarUnreadBadge
            v-if="rolledUpBadgeCount"
            :count="rolledUpBadgeCount"
            :tone="rolledUpBadgeTone"
            :title="badgeTitle"
            class="absolute -top-1 ltr:-right-1 rtl:-left-1"
          />
        </component>
        <SidebarCollapsedPopover
          v-if="hasChildren && isPopoverOpen"
          :label="label"
          :children="children"
          :active-child="activeChild"
          :trigger-rect="triggerRect"
          @close="closePopover"
          @mouseenter="handlePopoverMouseEnter"
          @mouseleave="handlePopoverMouseLeave"
          @sort-toggle="handleSortToggle"
        />
      </div>
    </template>
    <!-- Expanded State -->
    <template v-else>
      <SidebarGroupHeader
        :icon
        :name
        :label
        :to
        :getter-keys="getterKeys"
        :badge-count="areChildrenVisible ? badgeCount : rolledUpBadgeCount"
        :badge-tone="areChildrenVisible ? badgeTone : rolledUpBadgeTone"
        :badge-title="badgeTitle"
        :badge-to="badgeTo"
        :is-active="isActive"
        :has-active-child="hasActiveChild"
        :expandable="hasChildren"
        :is-expanded="isOpen"
        @toggle="toggleTrigger"
        @activate="handleActivate"
      />
      <!-- Grid-rows reveal: the row track animates between 0fr and 1fr so the
           children slide open at their natural height, no measuring needed. -->
      <div
        v-if="hasChildren"
        class="grid transition-[grid-template-rows] duration-200 ease-out motion-reduce:transition-none"
        :class="
          isOpen ? '[grid-template-rows:1fr]' : '[grid-template-rows:0fr]'
        "
      >
        <!-- Clipped children stay in the DOM for the animation, so they are
             taken out of the tab order while the group is folded. -->
        <ul
          :inert="isOpen ? undefined : true"
          class="grid overflow-hidden m-0 list-none min-w-0 min-h-0"
        >
          <template v-for="child in visibleChildren" :key="child.name">
            <SidebarSubGroup
              v-if="child.children"
              :name="`${name}:${child.name}`"
              :label="child.label"
              :icon="child.icon"
              :children="child.children"
              :collapsible="child.collapsible"
              :show-tree-line="child.showTreeLine"
              :end-tree-line="child.showTreeLine && isLastVisibleChild(child)"
              :is-expanded="isOpen"
              :active-child="activeChild"
              :sort-options="child.sortOptions"
              :active-sort="child.activeSort"
              @update-sort="child.onSortChange"
            />
            <SidebarGroupLeaf
              v-else-if="isAllowed(child.to)"
              v-bind="child"
              :active="activeChild?.name === child.name"
            />
          </template>
        </ul>
      </div>
      <ul v-else-if="isExpandable && isOpen">
        <SidebarGroupEmptyLeaf />
      </ul>
    </template>
  </Policy>
</template>
