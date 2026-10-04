<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { formatDuration } from 'shared/helpers/timeHelper';
import {
  PATHORS_ALERT_LEVEL,
  highestAlertLevel,
  isAiHandlingCall,
} from 'dashboard/helper/pathorsLiveCall';

// One live Pathors call in the pinned group at the top of the conversation
// list. The parent owns the clock and the alerts so sorting and rows agree.

const props = defineProps({
  // A record of the pathorsLiveCalls store.
  call: { type: Object, required: true },
  callerName: { type: String, default: '' },
  inboxName: { type: String, default: '' },
  elapsedSeconds: { type: Number, default: 0 },
  alerts: { type: Array, default: () => [] },
  to: { type: Object, required: true },
  isSelected: { type: Boolean, default: false },
});

const STRIPE_CLASS = {
  [PATHORS_ALERT_LEVEL.RED]: 'bg-n-ruby-9',
  [PATHORS_ALERT_LEVEL.AMBER]: 'bg-n-amber-9',
};
// Tinted surface + text for the phone tile and the alert chips.
const TONE_CLASS = {
  [PATHORS_ALERT_LEVEL.RED]: 'bg-n-ruby-3 text-n-ruby-11',
  [PATHORS_ALERT_LEVEL.AMBER]: 'bg-n-amber-3 text-n-amber-11',
};

const { t } = useI18n();

const isAiHandling = computed(() => isAiHandlingCall(props.call));
const level = computed(() => highestAlertLevel(props.alerts));
const durationLabel = computed(() => formatDuration(props.elapsedSeconds));
const statusLabel = computed(() => {
  if (!isAiHandling.value) {
    return t('CHAT_LIST.PATHORS_LIVE_CALLS.TAKEN_OVER', {
      agentName: props.call.acceptedByAgentName,
      duration: durationLabel.value,
    });
  }
  return t('CHAT_LIST.PATHORS_LIVE_CALLS.AI_HANDLING', {
    duration: durationLabel.value,
    turns: props.call.live?.turns ?? 0,
    interruptions: props.call.live?.interruptions ?? 0,
  });
});

const tileClass = computed(() => {
  if (!isAiHandling.value) return 'bg-n-blue-3 text-n-blue-11';
  return TONE_CLASS[level.value] || 'bg-n-teal-3 text-n-teal-11';
});
</script>

<template>
  <RouterLink
    :to="to"
    class="relative flex gap-2.5 px-4 py-2.5 border-b border-n-weak hover:bg-n-alpha-1"
    :class="{ 'bg-n-alpha-2': isSelected }"
    data-test-id="pathors-live-call-row"
  >
    <span
      v-if="level"
      class="absolute inset-y-0 start-0 w-[0.1875rem]"
      :class="STRIPE_CLASS[level]"
    />
    <span
      class="flex items-center justify-center rounded-lg size-8 shrink-0"
      :class="tileClass"
    >
      <Icon icon="i-ph-phone-bold" class="size-4" />
    </span>
    <span class="flex flex-col flex-1 min-w-0 gap-0.5">
      <span class="flex items-baseline justify-between gap-2 min-w-0">
        <span class="text-sm font-medium truncate text-n-slate-12">
          {{ callerName }}
        </span>
        <span class="text-xs truncate text-n-slate-10 shrink-0 max-w-[45%]">
          {{ inboxName }}
        </span>
      </span>
      <span
        class="flex items-center gap-1.5 min-w-0 text-xs"
        :class="isAiHandling ? 'text-n-teal-11' : 'text-n-blue-11'"
        data-test-id="pathors-live-call-status"
      >
        <span
          class="rounded-full size-1.5 shrink-0 bg-current"
          :class="{ 'animate-pulse': isAiHandling }"
        />
        <span class="truncate tabular-nums">
          {{ statusLabel }}
        </span>
      </span>
      <span v-if="alerts.length" class="flex flex-wrap gap-1 mt-0.5">
        <span
          v-for="alert in alerts"
          :key="alert.type"
          class="inline-flex items-center gap-1 px-1.5 rounded-md text-xs font-medium leading-5"
          :class="TONE_CLASS[alert.level]"
          data-test-id="pathors-live-call-chip"
        >
          <Icon icon="i-ph-warning-bold" class="size-3 shrink-0" />
          {{ t(alert.labelKey, alert.params) }}
        </span>
      </span>
    </span>
  </RouterLink>
</template>
