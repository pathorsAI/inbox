<script setup>
import { ref } from 'vue';
import { FocusScope } from 'reka-ui';
import { useDropdownPosition } from 'dashboard/composables/useDropdownPosition';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';

const { trigger } = defineProps({
  trigger: {
    type: Function,
    required: true,
  },
});

const menuRef = ref(null);

const { fixedPosition } = useDropdownPosition(trigger, menuRef, true, {
  align: 'start',
});
</script>

<template>
  <TeleportWithDirection to="body">
    <div
      data-dropdown-menu
      class="overflow-y-auto"
      :class="fixedPosition.class"
      :style="fixedPosition.style"
    >
      <FocusScope ref="menuRef" as="div" class="[&>*]:!static">
        <slot />
      </FocusScope>
    </div>
  </TeleportWithDirection>
</template>
