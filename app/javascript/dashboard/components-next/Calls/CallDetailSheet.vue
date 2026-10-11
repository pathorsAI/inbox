<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { format } from 'date-fns';
import { useAlert } from 'dashboard/composables';
import { useClock } from 'dashboard/composables/useClock';
import { formatDuration } from 'shared/helpers/timeHelper';
import PathorsCallsAPI from 'dashboard/api/pathorsCalls';
import { usePathorsLiveCallsStore } from 'dashboard/stores/pathorsLiveCalls';
import {
  usePathorsCallSession,
  PATHORS_JOIN_ERROR_LABELS,
} from 'dashboard/composables/usePathorsCallSession';
import {
  CALL_STATE,
  CALL_TONE,
  minutesSince,
  outcomeLabelKey,
  primaryCallState,
  toEpochMs,
} from 'dashboard/helper/pathorsCallState';
import {
  callElapsedSeconds,
  isLiveCallStatus,
} from 'dashboard/helper/pathorsLiveCall';
import AudioPlayer from 'dashboard/components-next/audio/AudioPlayer.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import CallTranscript from './CallTranscript.vue';
import { summaryText, useCallStateText } from './useCallStateText';
import { callerName, callerNumber, lineName } from './constants';

// The detail of one call, docked to the right of the calls page. Not modal:
// the table stays usable beside it, so it neither locks scrolling nor traps
// focus; Escape and the close button dismiss it.

const props = defineProps({
  // A calls-list row merged with the live store (see mergeLiveCall), or a
  // live store record when the call is not on the current page.
  call: { type: Object, required: true },
  accountId: { type: Number, required: true },
  currentUserId: { type: Number, default: null },
});

const emit = defineEmits(['close', 'dismissed', 'followUpResolved']);

const STATUS_BAR_CLASS = {
  [CALL_TONE.RUBY]: 'bg-n-ruby-2 outline-n-ruby-5 text-n-ruby-12',
  [CALL_TONE.BLUE]: 'bg-n-blue-2 outline-n-blue-5 text-n-blue-12',
  [CALL_TONE.SLATE]: 'bg-n-alpha-1 outline-n-weak text-n-slate-12',
};
const ENDED_FORMAT = 'MM/dd HH:mm';

const { t } = useI18n();
const now = useClock();
const liveCallsStore = usePathorsLiveCallsStore();
const session = usePathorsCallSession();
const { stateDetail } = useCallStateText();

const state = computed(() =>
  primaryCallState(props.call, {
    now: now.value,
    currentUserId: props.currentUserId,
  })
);
const isLive = computed(() => isLiveCallStatus(props.call.status));
const live = computed(() => props.call.live || {});
const startedAtMs = computed(() =>
  toEpochMs(props.call.startedAt ?? props.call.createdAt)
);
const elapsedSeconds = computed(() =>
  callElapsedSeconds(startedAtMs.value, now.value)
);

const title = computed(
  () =>
    callerName(props.call) ||
    callerNumber(props.call) ||
    t('CALLS_PAGE.TABLE.UNKNOWN_CALLER')
);
const subtitle = computed(() =>
  [callerName(props.call) && callerNumber(props.call), lineName(props.call)]
    .filter(Boolean)
    .join(' · ')
);
const endedLabel = computed(() => {
  const endedAt =
    toEpochMs(props.call.endedAt) ||
    (startedAtMs.value &&
      startedAtMs.value + (props.call.durationSeconds || 0) * 1000);
  return endedAt ? format(new Date(endedAt), ENDED_FORMAT) : '';
});

const conversationRoute = computed(() => ({
  name: 'inbox_conversation',
  params: {
    accountId: props.accountId,
    conversation_id:
      props.call.conversation?.displayId ?? props.call.conversationId,
  },
  query: props.call.messageId ? { messageId: props.call.messageId } : {},
}));

// --- Status bar ---------------------------------------------------------------

const isNeedsHuman = computed(() =>
  [CALL_STATE.REQUESTED, CALL_STATE.TRANSFER_FAILED].includes(state.value.key)
);
const isFollowUp = computed(
  () => state.value.key === CALL_STATE.ENDED && !!props.call.followUp
);
const isInThisCall = computed(
  () => session.isJoined.value && session.isActiveCall(props.call.id)
);

const statusTone = computed(() => {
  if (isNeedsHuman.value || isFollowUp.value) return CALL_TONE.RUBY;
  if ([CALL_STATE.DIALING, CALL_STATE.HUMAN].includes(state.value.key)) {
    return CALL_TONE.BLUE;
  }
  return CALL_TONE.SLATE;
});

const statusTitle = computed(() => {
  const { key, labelKey, labelParams } = state.value;
  if (isNeedsHuman.value) {
    const minutes = minutesSince(state.value.at, now.value);
    return t('CALLS_PAGE.SHEET.SIGNAL_AGO', {
      label: t(labelKey),
      time: minutes
        ? t('CALLS_PAGE.ATTENTION.MINUTES_AGO', { minutes })
        : t('CALLS_PAGE.ATTENTION.JUST_NOW'),
    });
  }
  if (isFollowUp.value) return t('CALLS_PAGE.CHIPS.FOLLOW_UP');
  if (key === CALL_STATE.ENDED) {
    return [t(outcomeLabelKey(props.call.outcome)), endedLabel.value]
      .filter(Boolean)
      .join(' · ');
  }
  return t(labelKey, labelParams);
});

const statusDetail = computed(() => {
  const { key, alerts, joinDisabledReasonKey } = state.value;
  if (isFollowUp.value) return t(outcomeLabelKey(props.call.outcome));
  if (key === CALL_STATE.DIALING) {
    return [stateDetail(props.call, state.value), t(joinDisabledReasonKey)]
      .filter(Boolean)
      .join(' · ');
  }
  if (key === CALL_STATE.WARN) {
    return alerts.map(alert => t(alert.hintKey)).join(' · ');
  }
  if (key === CALL_STATE.ENDED) return '';
  return stateDetail(props.call, state.value);
});

const showTakeOver = computed(
  () =>
    !isInThisCall.value &&
    (state.value.canJoin || state.value.key === CALL_STATE.DIALING)
);
const isTakeOverDisabled = computed(
  () =>
    !state.value.canJoin || session.isJoined.value || session.isJoining.value
);
const showDismiss = computed(() => isNeedsHuman.value && !props.call.dismissed);

const takeOver = async () => {
  if (isTakeOverDisabled.value) return;
  const joined = await session.join({
    accountId: props.accountId,
    callId: props.call.id,
  });
  if (joined) return;
  useAlert(
    t(
      PATHORS_JOIN_ERROR_LABELS[session.error.value] ||
        'CONVERSATION.VOICE_CALL.JOIN_FAILED'
    )
  );
};

const hangUp = async () => {
  if (session.isHangingUp.value) return;
  const ended = await session.hangup({ accountId: props.accountId });
  if (!ended) useAlert(t('CONVERSATION.VOICE_CALL.HANGUP_FAILED'));
};

const dismiss = async () => {
  try {
    await liveCallsStore.dismiss(props.call.id);
    emit('dismissed', props.call.id);
  } catch {
    useAlert(t('CALLS_PAGE.ATTENTION.DISMISS_FAILED'));
  }
};

const isResolvingFollowUp = ref(false);
const resolveFollowUp = async () => {
  isResolvingFollowUp.value = true;
  try {
    await PathorsCallsAPI.resolveFollowUp(props.call.id, props.accountId);
    emit('followUpResolved', props.call.id);
  } catch {
    useAlert(t('CALLS_PAGE.SHEET.RESOLVE_FOLLOW_UP_FAILED'));
  } finally {
    isResolvingFollowUp.value = false;
  }
};

// --- Side column ---------------------------------------------------------------

const summary = computed(() => props.call.summary || null);
const summaryTodos = computed(() => summary.value?.todos || []);

const isMissing = value =>
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
  Object.entries(props.call.variables || {}).map(([key, value]) => ({
    key,
    isMissing: isMissing(value),
    text: isMissing(value)
      ? t('CALLS_PAGE.SHEET.NOT_CAPTURED')
      : formatValue(value),
  }))
);

const metrics = computed(() => [
  {
    key: 'duration',
    label: t('CALLS_PAGE.SHEET.METRIC_DURATION'),
    value: formatDuration(
      isLive.value ? elapsedSeconds.value : props.call.durationSeconds
    ),
  },
  {
    key: 'turns',
    label: t('CALLS_PAGE.SHEET.METRIC_TURNS'),
    value: live.value.turns ?? '',
  },
  {
    key: 'interruptions',
    label: t('CALLS_PAGE.SHEET.METRIC_INTERRUPTIONS'),
    value: live.value.interruptions ?? '',
  },
]);

const handlerName = computed(() => {
  if (state.value.key === CALL_STATE.HUMAN) {
    return t(state.value.labelKey, state.value.labelParams);
  }
  return props.call.agent?.name || props.call.acceptedByAgentName || '';
});

const callFacts = computed(() =>
  [
    {
      key: 'number',
      label: t('CALLS_PAGE.SHEET.FACT_NUMBER'),
      value: callerNumber(props.call),
    },
    {
      key: 'line',
      label: t('CALLS_PAGE.SHEET.FACT_LINE'),
      value: lineName(props.call),
    },
    {
      key: 'handler',
      label: t('CALLS_PAGE.SHEET.FACT_HANDLER'),
      value: handlerName.value,
    },
  ].filter(fact => fact.value)
);

// --- Lifecycle -------------------------------------------------------------------

// The attention alerts leave out the call the agent is already looking at.
watch(
  () => props.call.id,
  id => liveCallsStore.setOpenCallId(id),
  { immediate: true }
);

const onKeydown = event => {
  if (event.key !== 'Escape') return;
  // A dialog on top handles its own Escape.
  if (document.querySelector('dialog[open]')) return;
  emit('close');
};
// A plain listener rather than @vueuse's onKeyStroke: vueuse runs on its own
// copy of Vue (see composables/useClock), so its cleanup would never fire here.
onMounted(() => document.addEventListener('keydown', onKeydown));
onBeforeUnmount(() => {
  document.removeEventListener('keydown', onKeydown);
  liveCallsStore.setOpenCallId(null);
});
</script>

<template>
  <aside
    class="absolute inset-y-0 end-0 z-20 flex flex-col w-full max-w-[40rem] overflow-hidden border-s shadow-lg bg-n-surface-1 border-n-weak"
    :aria-label="title"
    data-test-id="call-detail-sheet"
  >
    <header
      class="flex items-start gap-3 px-5 py-4 border-b shrink-0 border-n-weak"
    >
      <div class="flex flex-col flex-1 min-w-0 gap-0.5">
        <h2 class="text-base font-medium truncate text-n-slate-12">
          {{ title }}
        </h2>
        <p v-if="subtitle" class="text-sm truncate text-n-slate-11">
          {{ subtitle }}
        </p>
      </div>
      <span
        v-if="isLive"
        class="inline-flex items-center gap-1.5 px-2 rounded-md text-xs font-medium leading-6 tabular-nums bg-n-teal-3 text-n-teal-11 shrink-0"
      >
        <span
          class="rounded-full size-1.5 bg-current motion-safe:animate-pulse"
        />
        {{ formatDuration(elapsedSeconds) }}
      </span>
      <span v-else class="text-xs leading-6 text-n-slate-10 shrink-0">
        {{ endedLabel }}
      </span>
      <RouterLink
        :to="conversationRoute"
        class="inline-flex items-center h-6 gap-1 px-2 text-xs rounded-md outline outline-1 -outline-offset-1 outline-n-weak text-n-slate-11 hover:bg-n-alpha-1 shrink-0"
      >
        {{ t('CALLS_PAGE.SHEET.OPEN_CONVERSATION') }}
        <Icon icon="i-lucide-arrow-up-right" class="size-3.5" />
      </RouterLink>
      <Button
        icon="i-lucide-x"
        variant="ghost"
        color="slate"
        size="xs"
        class="shrink-0"
        :title="t('CALLS_PAGE.SHEET.CLOSE')"
        @click="emit('close')"
      />
    </header>

    <div class="flex-1 min-h-0 overflow-y-auto">
      <section
        class="flex flex-col gap-2 p-3 mx-5 mt-4 rounded-lg outline outline-1 -outline-offset-1"
        :class="STATUS_BAR_CLASS[statusTone]"
        data-test-id="call-status-bar"
        :data-state="state.key"
      >
        <span class="text-sm font-medium truncate">{{ statusTitle }}</span>
        <p v-if="statusDetail" class="text-sm text-n-slate-11">
          {{ statusDetail }}
        </p>
        <div
          v-if="showTakeOver || showDismiss || isInThisCall || isFollowUp"
          class="flex flex-wrap items-center gap-2"
        >
          <Button
            v-if="showTakeOver"
            :label="t('CONVERSATION.VOICE_CALL.TAKE_OVER_CALL')"
            icon="i-lucide-phone"
            size="sm"
            :color="isNeedsHuman ? 'ruby' : 'slate'"
            :variant="isNeedsHuman ? 'solid' : 'outline'"
            :disabled="isTakeOverDisabled"
            :is-loading="session.isJoining.value"
            data-test-id="call-take-over"
            @click="takeOver"
          />
          <Button
            v-if="showDismiss"
            :label="t('CALLS_PAGE.ATTENTION.DISMISS')"
            size="sm"
            variant="ghost"
            color="slate"
            data-test-id="call-dismiss"
            @click="dismiss"
          />
          <template v-if="isInThisCall">
            <Button
              v-if="session.isAudioBlocked.value"
              :label="t('CONVERSATION.VOICE_CALL.ENABLE_AUDIO')"
              icon="i-lucide-volume-2"
              size="sm"
              color="teal"
              @click="session.enableAudio"
            />
            <Button
              :label="t('CONVERSATION.VOICE_CALL.HANGUP_CALL')"
              icon="i-lucide-phone-off"
              size="sm"
              color="ruby"
              :is-loading="session.isHangingUp.value"
              :disabled="session.isHangingUp.value"
              data-test-id="call-hang-up"
              @click="hangUp"
            />
            <span class="text-sm tabular-nums text-n-slate-11">
              {{ formatDuration(session.durationSeconds.value) }}
            </span>
          </template>
          <Button
            v-if="isFollowUp"
            :label="t('CALLS_PAGE.SHEET.RESOLVE_FOLLOW_UP')"
            icon="i-lucide-check"
            size="sm"
            color="ruby"
            :is-loading="isResolvingFollowUp"
            :disabled="isResolvingFollowUp"
            data-test-id="call-resolve-follow-up"
            @click="resolveFollowUp"
          />
        </div>
      </section>

      <div class="flex flex-col gap-6 p-5 md:flex-row">
        <section class="flex flex-col flex-1 min-w-0 gap-3">
          <h3 class="text-xs font-medium text-n-slate-11">
            {{ t('CALLS_PAGE.SHEET.TRANSCRIPT') }}
          </h3>
          <CallTranscript
            :entries="live.transcript || []"
            :seq="live.seq || 0"
            :is-live="isLive"
            class="max-h-[32rem]"
          />
        </section>

        <div class="flex flex-col gap-5 md:w-56 shrink-0">
          <section v-if="summary" class="flex flex-col gap-1.5">
            <h3 class="text-xs font-medium text-n-slate-11">
              {{ t('CALLS_PAGE.SHEET.SUMMARY') }}
            </h3>
            <p class="text-sm text-n-slate-12">{{ summaryText(summary) }}</p>
            <ul
              v-if="summaryTodos.length"
              class="flex flex-col gap-1 ps-4 text-sm list-disc text-n-slate-12"
            >
              <li v-for="todo in summaryTodos" :key="todo">{{ todo }}</li>
            </ul>
          </section>

          <section v-if="variables.length" class="flex flex-col gap-1.5">
            <h3 class="text-xs font-medium text-n-slate-11">
              {{ t('CALLS_PAGE.SHEET.VARIABLES') }}
            </h3>
            <dl class="flex flex-col gap-1 text-sm">
              <div
                v-for="variable in variables"
                :key="variable.key"
                class="flex justify-between gap-3"
              >
                <dt class="truncate text-n-slate-11">{{ variable.key }}</dt>
                <dd
                  class="text-end break-words"
                  :class="
                    variable.isMissing ? 'text-n-slate-9' : 'text-n-slate-12'
                  "
                >
                  {{ variable.text }}
                </dd>
              </div>
            </dl>
          </section>

          <section class="flex flex-col gap-1.5">
            <h3 class="text-xs font-medium text-n-slate-11">
              {{ t('CALLS_PAGE.SHEET.METRICS') }}
            </h3>
            <dl class="grid grid-cols-3 gap-2">
              <div
                v-for="metric in metrics"
                :key="metric.key"
                class="flex flex-col gap-0.5"
              >
                <dt class="text-xs text-n-slate-10">{{ metric.label }}</dt>
                <dd class="text-sm font-medium tabular-nums text-n-slate-12">
                  {{ metric.value }}
                </dd>
              </div>
            </dl>
          </section>

          <section v-if="callFacts.length" class="flex flex-col gap-1.5">
            <h3 class="text-xs font-medium text-n-slate-11">
              {{ t('CALLS_PAGE.SHEET.CALL') }}
            </h3>
            <dl class="flex flex-col gap-1 text-sm">
              <div
                v-for="fact in callFacts"
                :key="fact.key"
                class="flex justify-between gap-3"
              >
                <dt class="text-n-slate-11 shrink-0">{{ fact.label }}</dt>
                <dd class="truncate text-end text-n-slate-12">
                  {{ fact.value }}
                </dd>
              </div>
            </dl>
          </section>

          <section v-if="call.recordingUrl" class="flex flex-col gap-1.5">
            <h3 class="text-xs font-medium text-n-slate-11">
              {{ t('CALLS_PAGE.SHEET.RECORDING') }}
            </h3>
            <AudioPlayer
              :src="call.recordingUrl"
              :fallback-duration="call.durationSeconds || 0"
            />
          </section>
        </div>
      </div>
    </div>
  </aside>
</template>
