<script setup>
import { ref } from 'vue';
import { FocusScope } from 'reka-ui';
import { vOnClickOutside } from '@vueuse/components';
import DropdownFloating from './DropdownFloating.vue';
import { provideDropdownContext, useDropdownTeleport } from './provider.js';

const emit = defineEmits(['close']);

const isOpen = ref(false);
const toggle = value => {
  isOpen.value = value ?? !isOpen.value;
};

const teleport = useDropdownTeleport();
const containerRef = ref(null);

// A getter, not a computed: consumers swap the trigger element as their state changes — a multi
// select trades its placeholder for a chips button once something is picked.
const getTrigger = () => containerRef.value?.firstElementChild ?? null;

const closeMenu = () => {
  if (isOpen.value) {
    emit('close');
    toggle(false);
  }
};

// A teleported menu sits outside the container, so clicks inside it read as clicks outside.
const clickOutsideHandler = [closeMenu, { ignore: ['[data-dropdown-menu]'] }];

provideDropdownContext({
  isOpen,
  toggle,
  closeMenu,
});
</script>

<template>
  <div
    ref="containerRef"
    v-on-click-outside="clickOutsideHandler"
    class="relative space-y-2"
  >
    <slot name="trigger" :is-open :toggle="() => toggle()" />
    <template v-if="isOpen">
      <DropdownFloating v-if="teleport" :trigger="getTrigger">
        <slot />
      </DropdownFloating>
      <FocusScope v-else as="div" class="absolute">
        <slot />
      </FocusScope>
    </template>
  </div>
</template>
