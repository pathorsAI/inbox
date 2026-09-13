<script setup>
import { computed } from 'vue';
import {
  CollapsibleContent,
  CollapsibleRoot,
  CollapsibleTrigger,
} from 'reka-ui';

defineProps({
  disabled: {
    type: Boolean,
    default: false,
  },
});

const open = defineModel('open', {
  type: Boolean,
  default: false,
});

// Handed to the trigger slot so callers get the shared chevron motion without
// restating it on every disclosure row.
const chevronClass = computed(() => [
  'i-lucide-chevron-down size-4 flex-shrink-0 transition-transform duration-fast ease-out-soft motion-reduce:transition-none',
  open.value ? 'rotate-180' : '',
]);
</script>

<template>
  <CollapsibleRoot v-model:open="open" :disabled="disabled">
    <CollapsibleTrigger class="w-full text-start">
      <slot name="trigger" :open="open" :chevron-class="chevronClass" />
    </CollapsibleTrigger>
    <div
      class="grid transition-[grid-template-rows] duration-base ease-out-soft motion-reduce:transition-none"
      :class="open ? '[grid-template-rows:1fr]' : '[grid-template-rows:0fr]'"
    >
      <CollapsibleContent
        class="min-h-0 overflow-hidden duration-base data-[state=open]:animate-in data-[state=open]:fade-in-0 data-[state=closed]:animate-out data-[state=closed]:fade-out-0 motion-reduce:animate-none"
      >
        <slot />
      </CollapsibleContent>
    </div>
  </CollapsibleRoot>
</template>
