<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { useClock } from 'dashboard/composables/useClock';
import { formatDuration } from 'shared/helpers/timeHelper';
import {
  PATHORS_ALERT_LEVEL,
  PATHORS_ALERT_TYPE,
  callElapsedSeconds,
  getPathorsCallAlerts,
} from 'dashboard/helper/pathorsLiveCall';

// What the AI is doing on a live Pathors call, shown in the voice_call bubble
// until someone takes the call over: running counters, one banner per alert,
// and the transcript window the backend pushes on every turn.

const props = defineProps({
  // The camelized `call` of the voice_call message.
  call: { type: Object, required: true },
  // Its live state from the pathorsLiveCalls store; null until the first turn.
  live: { type: Object, default: null },
});

// How close to the bottom still counts as "following along", so a new line
// keeps the box pinned there instead of leaving the reader behind.
const STICK_TO_BOTTOM_PX = 24;
const ENTRY_KIND = { MESSAGE: 'message', SYSTEM: 'system' };
const ROLE_ASSISTANT = 'assistant';
const SYSTEM_CODE_TRANSFER_FAILED = 'transfer_failed';

const ALERT_BANNER_CLASS = {
  [PATHORS_ALERT_LEVEL.RED]: 'bg-n-ruby-3 text-n-ruby-11',
  [PATHORS_ALERT_LEVEL.AMBER]: 'bg-n-amber-3 text-n-amber-11',
};

const { t } = useI18n();
const now = useClock();

const live = computed(() => props.live || {});
const elapsedSeconds = computed(() =>
  callElapsedSeconds(props.call.startedAt, now.value)
);
const alerts = computed(() =>
  getPathorsCallAlerts(
    { ...props.call, live: props.live },
    elapsedSeconds.value
  )
);
const isOver = type => alerts.value.some(alert => alert.type === type);

const stats = computed(() => [
  {
    key: 'duration',
    label: t('CONVERSATION.VOICE_CALL.LIVE.STAT_DURATION'),
    value: formatDuration(elapsedSeconds.value),
    isOver: isOver(PATHORS_ALERT_TYPE.LONG_CALL),
  },
  {
    key: 'turns',
    label: t('CONVERSATION.VOICE_CALL.LIVE.STAT_TURNS'),
    value: live.value.turns ?? 0,
    isOver: isOver(PATHORS_ALERT_TYPE.MANY_TURNS),
  },
  {
    key: 'interruptions',
    label: t('CONVERSATION.VOICE_CALL.LIVE.STAT_INTERRUPTIONS'),
    value: live.value.interruptions ?? 0,
    isOver: isOver(PATHORS_ALERT_TYPE.INTERRUPTIONS),
  },
]);

const entries = computed(() =>
  (live.value.transcript || []).map((entry, index) => ({
    ...entry,
    key: `${entry.at ?? ''}-${index}`,
    isAssistant: entry.role === ROLE_ASSISTANT,
    isSystem: entry.kind === ENTRY_KIND.SYSTEM,
    isFailure: entry.code === SYSTEM_CODE_TRANSFER_FAILED,
  }))
);
const messageCount = computed(
  () => entries.value.filter(entry => entry.kind === ENTRY_KIND.MESSAGE).length
);

const transcriptRef = ref(null);
const isFollowing = ref(true);

const onTranscriptScroll = () => {
  const el = transcriptRef.value;
  if (!el) return;
  isFollowing.value =
    el.scrollHeight - el.scrollTop - el.clientHeight <= STICK_TO_BOTTOM_PX;
};

const scrollToBottom = () => {
  const el = transcriptRef.value;
  if (el) el.scrollTop = el.scrollHeight;
};

watch(
  () => live.value.seq,
  async () => {
    if (!isFollowing.value) return;
    await nextTick();
    scrollToBottom();
  },
  { immediate: true, flush: 'post' }
);
</script>

<template>
  <div class="flex flex-col gap-2" data-test-id="pathors-live-monitor">
    <div
      class="grid grid-cols-3 overflow-hidden border rounded-lg border-n-weak"
    >
      <div
        v-for="stat in stats"
        :key="stat.key"
        class="flex flex-col gap-0.5 px-2.5 py-1.5 border-e border-n-weak last:border-e-0"
        :data-test-id="`live-stat-${stat.key}`"
        :data-over="stat.isOver"
      >
        <span class="text-xs text-n-slate-10">{{ stat.label }}</span>
        <strong
          class="text-sm font-semibold tabular-nums"
          :class="stat.isOver ? 'text-n-amber-11' : 'text-n-slate-12'"
        >
          {{ stat.value }}
        </strong>
      </div>
    </div>

    <div
      v-for="alert in alerts"
      :key="alert.type"
      class="flex items-start gap-2 px-2.5 py-2 text-sm rounded-lg"
      :class="ALERT_BANNER_CLASS[alert.level]"
      data-test-id="live-alert"
    >
      <Icon icon="i-ph-warning-bold" class="size-4 mt-0.5 shrink-0" />
      <span class="flex flex-wrap gap-x-1.5">
        <strong class="font-semibold">
          {{ t(alert.labelKey, alert.params) }}
        </strong>
        <span>{{ t(alert.hintKey) }}</span>
      </span>
    </div>

    <div
      v-if="entries.length"
      class="flex flex-col overflow-hidden border rounded-lg border-n-weak bg-n-surface-2"
    >
      <div
        class="flex items-center justify-between px-2.5 py-1.5 text-xs border-b border-n-weak text-n-slate-11"
      >
        <span
          class="inline-flex items-center gap-1.5 font-medium text-n-teal-11"
        >
          <span class="rounded-full size-1.5 bg-current animate-pulse" />
          {{ t('CONVERSATION.VOICE_CALL.LIVE.TRANSCRIPT_TITLE') }}
        </span>
        <span class="tabular-nums" data-test-id="live-transcript-count">
          {{
            t(
              'CONVERSATION.VOICE_CALL.LIVE.TRANSCRIPT_COUNT',
              { count: messageCount },
              messageCount
            )
          }}
        </span>
      </div>
      <ol
        ref="transcriptRef"
        class="flex flex-col gap-2 p-2.5 overflow-y-auto max-h-[14.375rem]"
        data-test-id="live-transcript"
        @scroll="onTranscriptScroll"
      >
        <template v-for="entry in entries" :key="entry.key">
          <li
            v-if="entry.isSystem"
            class="self-center inline-flex items-center gap-1 text-xs text-center"
            :class="
              entry.isFailure ? 'font-medium text-n-ruby-11' : 'text-n-slate-10'
            "
            data-test-id="live-system-line"
          >
            <Icon
              v-if="entry.isFailure"
              icon="i-ph-warning-bold"
              class="size-3 shrink-0"
            />
            {{ entry.text }}
          </li>
          <li
            v-else
            class="flex flex-col gap-0.5 max-w-[88%]"
            :class="entry.isAssistant ? 'self-end items-end' : 'self-start'"
            :data-test-id="
              entry.isAssistant ? 'live-assistant-line' : 'live-user-line'
            "
          >
            <span class="flex gap-1.5 text-xs text-n-slate-10">
              {{
                entry.isAssistant
                  ? t('CONVERSATION.VOICE_CALL.LIVE.ROLE_ASSISTANT')
                  : t('CONVERSATION.VOICE_CALL.LIVE.ROLE_USER')
              }}
              <span v-if="entry.interrupted" class="text-n-amber-11">
                {{ t('CONVERSATION.VOICE_CALL.LIVE.INTERRUPTED') }}
              </span>
            </span>
            <p
              class="px-2.5 py-1.5 text-sm leading-relaxed whitespace-pre-wrap break-words rounded-xl text-n-slate-12"
              :class="[
                entry.isAssistant ? 'bg-n-blue-3' : 'bg-n-slate-3',
                {
                  'outline-dashed outline-1 outline-n-amber-9':
                    entry.interrupted,
                },
              ]"
            >
              {{ entry.content }}
            </p>
          </li>
        </template>
      </ol>
    </div>
  </div>
</template>
