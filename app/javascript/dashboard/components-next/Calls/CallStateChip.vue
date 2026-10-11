<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { CALL_STATE } from 'dashboard/helper/pathorsCallState';
import { CALL_TONE_CHIP_CLASS } from './constants';

// The primary state of a call (see helper/pathorsCallState) as a chip, shared
// by the calls table, the detail sheet and the voice_call bubble.

const props = defineProps({
  // The result of primaryCallState.
  state: { type: Object, required: true },
});

const { t } = useI18n();

// Someone (the AI or a person) is talking to the caller right now.
const ON_THE_LINE = [
  CALL_STATE.AI,
  CALL_STATE.WARN,
  CALL_STATE.HUMAN,
  CALL_STATE.LIVE,
  CALL_STATE.REQUESTED,
  CALL_STATE.TRANSFER_FAILED,
];

const label = computed(() => t(props.state.labelKey, props.state.labelParams));
const isOnTheLine = computed(() => ON_THE_LINE.includes(props.state.key));
</script>

<template>
  <span
    class="inline-flex items-center gap-1.5 px-2 rounded-md text-xs font-medium leading-6 whitespace-nowrap"
    :class="CALL_TONE_CHIP_CLASS[state.tone]"
    :data-state="state.key"
    data-test-id="call-state-chip"
  >
    <span
      v-if="isOnTheLine"
      class="rounded-full size-1.5 shrink-0 bg-current motion-safe:animate-pulse"
    />
    {{ label }}
  </span>
</template>
