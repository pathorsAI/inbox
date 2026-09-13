<script setup>
import { computed, getCurrentInstance, ref, watch } from 'vue';
import { CollapsibleRoot, CollapsibleTrigger } from 'reka-ui';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  title: { type: String, required: true },
  isOpen: { type: Boolean, default: false },
});

const isExpanded = ref(props.isOpen);
const { uid } = getCurrentInstance();
const contentId = computed(() => `accordion-content-${uid}`);

watch(
  () => props.isOpen,
  newValue => {
    isExpanded.value = newValue;
  }
);
</script>

<template>
  <CollapsibleRoot
    v-model:open="isExpanded"
    class="border rounded-lg border-n-slate-4"
  >
    <CollapsibleTrigger
      :aria-controls="contentId"
      class="flex items-center justify-between w-full gap-3 p-4 text-start rounded-lg outline-none hover:bg-n-alpha-2 focus-visible:ring-1 focus-visible:ring-n-brand"
    >
      <span class="text-sm font-medium text-n-slate-12">{{ title }}</span>
      <Icon
        icon="i-lucide-chevron-down"
        class="w-4 h-4 text-n-slate-11 transition-transform duration-fast ease-out-soft motion-reduce:transition-none"
        :class="{ 'rotate-180': isExpanded }"
      />
    </CollapsibleTrigger>
    <div
      class="grid transition-[grid-template-rows] duration-base ease-out-soft motion-reduce:transition-none"
      :class="
        isExpanded ? '[grid-template-rows:1fr]' : '[grid-template-rows:0fr]'
      "
    >
      <div class="min-h-0 overflow-hidden">
        <div v-if="isExpanded" :id="contentId" class="p-4 pt-0">
          <slot />
        </div>
      </div>
    </div>
  </CollapsibleRoot>
</template>
