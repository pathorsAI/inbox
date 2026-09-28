<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { format } from 'date-fns';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { useMessageContext } from '../provider.js';

// Only the tail of the conversation matters when picking the call up; the rest
// is one click away.
const COLLAPSED_TURN_COUNT = 3;
const TIME_FORMAT = 'HH:mm';
const ROLE_ASSISTANT = 'assistant';

const { contentAttributes } = useMessageContext();
const { t } = useI18n();

const isExpanded = ref(false);

// Top-level keys arrive camelized; variable keys are kept verbatim (see the
// stopPaths in MessageList.vue).
const handoff = computed(() => contentAttributes.value?.data ?? {});
const transcript = computed(() => handoff.value.transcript ?? []);

const formatTime = timestamp =>
  timestamp ? format(new Date(timestamp), TIME_FORMAT) : '';

const isMissingValue = value =>
  value === null || value === undefined || value === '';

const formatValue = value => {
  if (typeof value === 'boolean') {
    return value
      ? t('CONVERSATION.PATHORS_HANDOFF.YES')
      : t('CONVERSATION.PATHORS_HANDOFF.NO');
  }
  if (typeof value === 'object') return JSON.stringify(value);
  return String(value);
};

const variables = computed(() =>
  Object.entries(handoff.value.variables ?? {}).map(([key, value]) => {
    const isMissing = isMissingValue(value);
    return {
      key,
      isMissing,
      text: isMissing
        ? t('CONVERSATION.PATHORS_HANDOFF.NOT_CAPTURED')
        : formatValue(value),
    };
  })
);

const capturedCount = computed(
  () => variables.value.filter(variable => !variable.isMissing).length
);

const durationLabel = computed(() => {
  const totalSeconds = handoff.value.aiDurationSeconds;
  if (totalSeconds === null || totalSeconds === undefined) return '';

  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return minutes
    ? t('CONVERSATION.PATHORS_HANDOFF.DURATION_MINUTES', { minutes, seconds })
    : t('CONVERSATION.PATHORS_HANDOFF.DURATION_SECONDS', { seconds });
});

const metaLine = computed(() => {
  const time = formatTime(handoff.value.transferredAt);
  if (!durationLabel.value) {
    return t('CONVERSATION.PATHORS_HANDOFF.META_WITHOUT_DURATION', { time });
  }
  return t('CONVERSATION.PATHORS_HANDOFF.META', {
    time,
    duration: durationLabel.value,
  });
});

const hiddenTurnCount = computed(() =>
  Math.max(transcript.value.length - COLLAPSED_TURN_COUNT, 0)
);

const visibleTurns = computed(() => {
  const turns = transcript.value.map((turn, index) => {
    const isAssistant = turn.role === ROLE_ASSISTANT;
    const role = isAssistant
      ? t('CONVERSATION.PATHORS_HANDOFF.ROLE_ASSISTANT')
      : t('CONVERSATION.PATHORS_HANDOFF.ROLE_USER');
    const time = formatTime(turn.timestamp);
    return {
      key: index,
      isAssistant,
      content: turn.content,
      label: time
        ? t('CONVERSATION.PATHORS_HANDOFF.TURN_LABEL', { role, time })
        : role,
    };
  });
  return isExpanded.value ? turns : turns.slice(-COLLAPSED_TURN_COUNT);
});

const toggleLabel = computed(() =>
  isExpanded.value
    ? t('CONVERSATION.PATHORS_HANDOFF.COLLAPSE')
    : t('CONVERSATION.PATHORS_HANDOFF.SHOW_EARLIER', {
        count: hiddenTurnCount.value,
      })
);

const toggleExpanded = () => {
  isExpanded.value = !isExpanded.value;
};
</script>

<template>
  <div
    class="w-full max-w-xl overflow-hidden border rounded-xl border-n-blue-5 bg-n-solid-1"
    data-bubble-name="pathors-handoff"
  >
    <div
      class="flex items-center gap-3 px-4 py-3 border-b bg-n-blue-2 border-n-blue-4"
    >
      <div
        class="flex items-center justify-center rounded-lg size-8 shrink-0 bg-n-blue-9 text-white"
      >
        <Icon icon="i-ph-sparkle-fill" class="size-4" />
      </div>
      <div class="flex flex-col min-w-0">
        <span class="text-heading-3 text-n-slate-12">
          {{ t('CONVERSATION.PATHORS_HANDOFF.TITLE') }}
        </span>
        <span class="text-label-small text-n-slate-11">{{ metaLine }}</span>
      </div>
    </div>

    <div class="px-4 py-3" data-test-id="handoff-variables">
      <template v-if="variables.length">
        <p class="mb-2 text-label-small text-n-slate-11">
          {{
            t('CONVERSATION.PATHORS_HANDOFF.VARIABLES_LABEL', {
              count: capturedCount,
            })
          }}
        </p>
        <dl class="grid grid-cols-2 gap-x-4 gap-y-3">
          <div
            v-for="variable in variables"
            :key="variable.key"
            class="min-w-0"
          >
            <dt class="font-mono text-xs break-all text-n-slate-11">
              {{ variable.key }}
            </dt>
            <dd
              class="mt-0.5 text-sm break-words"
              :class="
                variable.isMissing
                  ? 'text-n-slate-10'
                  : 'font-semibold text-n-slate-12'
              "
            >
              {{ variable.text }}
            </dd>
          </div>
        </dl>
      </template>
      <template v-else>
        <p class="mb-1 text-label-small text-n-slate-11">
          {{ t('CONVERSATION.PATHORS_HANDOFF.VARIABLES_LABEL_EMPTY') }}
        </p>
        <p class="text-sm text-n-slate-10">
          {{ t('CONVERSATION.PATHORS_HANDOFF.NO_VARIABLES') }}
        </p>
      </template>
    </div>

    <div
      v-if="transcript.length"
      class="px-4 py-3 border-t border-n-weak"
      data-test-id="handoff-transcript"
    >
      <div class="flex items-center justify-between gap-2 mb-2">
        <p class="text-label-small text-n-slate-11">
          {{
            t(
              'CONVERSATION.PATHORS_HANDOFF.TRANSCRIPT_LABEL',
              { count: transcript.length },
              transcript.length
            )
          }}
        </p>
        <button
          v-if="hiddenTurnCount"
          type="button"
          class="flex items-center gap-1 p-0 bg-transparent border-0 text-label-small text-n-blue-11 hover:text-n-blue-12"
          @click="toggleExpanded"
        >
          {{ toggleLabel }}
          <Icon
            :icon="isExpanded ? 'i-ph-caret-up-bold' : 'i-ph-caret-down-bold'"
            class="size-3"
          />
        </button>
      </div>
      <ol class="flex flex-col gap-2">
        <li
          v-for="turn in visibleTurns"
          :key="turn.key"
          class="flex flex-col gap-0.5"
          :class="turn.isAssistant ? 'items-end' : 'items-start'"
          data-test-id="handoff-turn"
        >
          <span class="text-xs text-n-slate-11">{{ turn.label }}</span>
          <p
            class="max-w-[82%] px-3 py-2 text-sm leading-relaxed whitespace-pre-wrap break-words rounded-2xl text-n-slate-12"
            :class="
              turn.isAssistant
                ? 'bg-n-blue-3 rounded-ee-md'
                : 'bg-n-slate-3 rounded-es-md'
            "
          >
            {{ turn.content }}
          </p>
        </li>
      </ol>
    </div>
  </div>
</template>
