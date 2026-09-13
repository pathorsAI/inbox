<script setup>
import { SwitchRoot, SwitchThumb } from 'reka-ui';
import { useI18n } from 'vue-i18n';

const emit = defineEmits(['change']);

const { t } = useI18n();

const modelValue = defineModel({
  type: Boolean,
  default: false,
});

const updateValue = value => {
  modelValue.value = value;
  emit('change', !value);
};
</script>

<template>
  <SwitchRoot
    :model-value="modelValue"
    class="group relative h-4 rounded-full w-7 flex-shrink-0 select-none focus:outline-none focus:ring-1 focus:ring-n-brand focus:ring-offset-n-slate-2 focus:ring-offset-2 transition-colors duration-fast ease-out-soft motion-reduce:transition-none data-[state=checked]:bg-n-brand data-[state=unchecked]:bg-n-slate-6"
    @update:model-value="updateValue"
  >
    <span class="sr-only">{{ t('SWITCH.TOGGLE') }}</span>
    <SwitchThumb
      class="absolute top-1/2 ltr:left-0.5 rtl:right-0.5 -translate-y-1/2 transition-transform duration-[350ms] ease-[cubic-bezier(0.34,1.56,0.64,1)] motion-reduce:transition-none data-[state=unchecked]:translate-x-0 data-[state=checked]:ltr:translate-x-3 data-[state=checked]:rtl:-translate-x-3 data-[state=checked]:group-active:ltr:translate-x-[6px] data-[state=checked]:group-active:rtl:-translate-x-[6px]"
    >
      <span
        class="block h-3 w-3 rounded-full bg-n-background shadow-md transition-[width] duration-[180ms] ease-in-out motion-reduce:transition-none group-active:w-[18px]"
      />
    </SwitchThumb>
  </SwitchRoot>
</template>
