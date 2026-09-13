<script setup>
import { computed, ref } from 'vue';
import {
  ConfigProvider,
  PopoverContent,
  PopoverPortal,
  PopoverRoot,
  PopoverTrigger,
} from 'reka-ui';
import { vOnClickOutside } from '@vueuse/components';
import {
  breakpointsTailwind,
  unrefElement,
  useBreakpoints,
  useEventListener,
} from '@vueuse/core';
import { useMapGetter } from 'dashboard/composables/store';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';

const props = defineProps({
  align: {
    type: String,
    default: 'end',
    validator: v => ['start', 'end'].includes(v),
  },
  disableMobileView: {
    type: Boolean,
    default: false,
  },
  closeOnScroll: {
    type: Boolean,
    default: true,
  },
  showContentBorder: {
    type: Boolean,
    default: true,
  },
});

const emit = defineEmits(['show', 'hide']);

const isActive = ref(false);
const triggerRef = ref(null);
const contentRef = ref(null);
const mobileContentRef = ref(null);

const isRTL = useMapGetter('accounts/isRTL');
// reka positions and mirrors `ltr:`/`rtl:` utilities off this, so the teleported
// content keeps the app's reading direction.
const direction = computed(() => (isRTL.value ? 'rtl' : 'ltr'));

const breakpoints = useBreakpoints(breakpointsTailwind);
const belowMd = breakpoints.smaller('md');
const isMobile = computed(() => !props.disableMobileView && belowMd.value);

const SCROLL_CLOSE_THRESHOLD = 24;
const triggerTopAtOpen = ref(0);

const setOpen = value => {
  if (value === isActive.value) return;
  isActive.value = value;
  if (value) {
    triggerTopAtOpen.value =
      unrefElement(triggerRef)?.getBoundingClientRect().top ?? 0;
    emit('show');
  } else {
    emit('hide');
  }
};

const show = () => setOpen(true);
const hide = () => setOpen(false);
const toggle = () => setOpen(!isActive.value);

// The teleported popover tracks its trigger while ancestors scroll; allow
// small drift (trackpad inertia), but close once the trigger moves further.
useEventListener(
  window,
  'scroll',
  event => {
    if (!props.closeOnScroll || !isActive.value || isMobile.value) return;
    if (contentRef.value?.contains(event.target)) return;
    const top = unrefElement(triggerRef)?.getBoundingClientRect().top ?? 0;
    if (Math.abs(top - triggerTopAtOpen.value) > SCROLL_CLOSE_THRESHOLD) {
      hide();
    }
  },
  { capture: true, passive: true }
);

// Selectors for teleported elements that should not trigger close
const clickOutsideIgnore = [
  'dialog.ProseMirror-prompt-backdrop',
  '[data-popover-content]',
];

// An overlay opened from inside the popover teleports out of it, so its own Escape handler
// registers after this one and cannot stop it. Leave Escape to whichever overlay the key
// was pressed in; closing the popover out from under it would discard the work in progress.
const isNestedOverlay = event => {
  const overlay = event.target?.closest?.(clickOutsideIgnore.join(','));
  if (!overlay) return false;
  // Our own content wraps the panel we render, so anything else is a nested overlay.
  return !(
    overlay.contains(contentRef.value) ||
    overlay.contains(mobileContentRef.value)
  );
};

const keepOpenForNestedOverlay = event => {
  if (isNestedOverlay(event)) event.preventDefault();
};

const handleClickOutside = event => {
  if (unrefElement(triggerRef)?.contains(event.target)) return;
  hide();
};

defineExpose({ show, hide, toggle });
</script>

<template>
  <ConfigProvider :dir="direction">
    <PopoverRoot :open="isActive" @update:open="setOpen">
      <PopoverTrigger ref="triggerRef" as="span" class="inline-flex">
        <slot :is-open="isActive" />
      </PopoverTrigger>

      <PopoverPortal v-if="!isMobile">
        <PopoverContent
          data-popover-content
          :align="align"
          :side-offset="8"
          :collision-padding="16"
          class="flex flex-col max-h-[var(--reka-popover-content-available-height)] bg-n-alpha-3 backdrop-blur-[100px] shadow-xl rounded-xl z-[9999] duration-fast ease-out-soft data-[state=open]:animate-in data-[state=open]:fade-in-0 data-[state=open]:zoom-in-95 data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=closed]:zoom-out-95 motion-reduce:animate-none"
          @escape-key-down="keepOpenForNestedOverlay"
          @pointer-down-outside="
            keepOpenForNestedOverlay($event.detail.originalEvent)
          "
          @focus-outside="$event.preventDefault()"
        >
          <div
            ref="contentRef"
            class="flex-1 min-h-0 overflow-y-auto overscroll-contain rounded-xl"
            :class="{ 'border border-n-strong': showContentBorder }"
          >
            <slot name="content" :hide="hide" />
          </div>
        </PopoverContent>
      </PopoverPortal>
    </PopoverRoot>
  </ConfigProvider>

  <!-- Mobile: centered modal with backdrop -->
  <TeleportWithDirection to="body">
    <div
      v-if="isActive && isMobile"
      data-popover-backdrop
      class="fixed inset-0 z-[9999] flex items-start pt-[clamp(3rem,15vh,12rem)] justify-center bg-n-alpha-black1 duration-fast ease-out-soft animate-in fade-in-0 motion-reduce:animate-none"
    >
      <div
        ref="mobileContentRef"
        v-on-click-outside="[
          handleClickOutside,
          { ignore: clickOutsideIgnore },
        ]"
        data-popover-content
        class="relative flex flex-col w-full max-w-lg max-h-[calc(100vh-4rem)] mx-4 bg-n-alpha-3 backdrop-blur-[100px] shadow-xl rounded-xl duration-fast ease-out-soft animate-in fade-in-0 zoom-in-95 motion-reduce:animate-none"
      >
        <div
          class="flex-1 min-h-0 overflow-y-auto overscroll-contain rounded-xl"
        >
          <slot name="content" :hide="hide" />
        </div>
      </div>
    </div>
  </TeleportWithDirection>
</template>
