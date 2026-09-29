<script setup>
import Button from 'dashboard/components-next/button/Button.vue';
import Popover from 'dashboard/components-next/popover/Popover.vue';

defineProps({
  options: {
    type: Array,
    required: true,
  },
  modelValue: {
    type: String,
    required: true,
  },
  label: {
    type: String,
    required: true,
  },
});

const emit = defineEmits(['update:modelValue']);

const handleSelect = (value, hide) => {
  emit('update:modelValue', value);
  hide();
};
</script>

<template>
  <Popover disable-mobile-view :show-content-border="false">
    <template #default="{ isOpen }">
      <Button
        icon="i-lucide-chevron-down"
        size="sm"
        trailing-icon
        color="slate"
        variant="faded"
        class="!w-fit max-w-40"
        :class="{ 'dark:!bg-n-alpha-2 !bg-n-slate-9/20': isOpen }"
        :label="label"
      />
    </template>
    <template #content="{ hide }">
      <div
        class="select-none max-w-64 flex flex-col gap-1 p-1 rounded-xl border border-n-weak dark:border-n-strong/50"
      >
        <Button
          v-for="option in options"
          :key="option.value"
          :label="option.label"
          :icon="option.value === modelValue ? 'i-lucide-check' : ''"
          size="sm"
          variant="ghost"
          color="slate"
          trailing-icon
          class="!justify-end !px-2.5 !h-7"
          :class="{ '!bg-n-alpha-2': option.value === modelValue }"
          @click="handleSelect(option.value, hide)"
        />
      </div>
    </template>
  </Popover>
</template>
