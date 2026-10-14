<script setup>
import {
  computed,
  onBeforeUnmount,
  onMounted,
  reactive,
  ref,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { format } from 'date-fns';
import { useAlert } from 'dashboard/composables';
import { useClock } from 'dashboard/composables/useClock';
import { formatDuration } from 'shared/helpers/timeHelper';
import PathorsCallsAPI from 'dashboard/api/pathorsCalls';
import { useCallNotes } from 'dashboard/composables/useCallNotes';
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
  PATHORS_ALERT_THRESHOLDS,
  callElapsedSeconds,
  isLiveCallStatus,
} from 'dashboard/helper/pathorsLiveCall';
import AudioPlayer from 'dashboard/components-next/audio/AudioPlayer.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import CallTranscript from './CallTranscript.vue';
import CallContactPopover from './CallContactPopover.vue';
import CallMetrics from './CallMetrics.vue';
import CallNoteCard from './CallNoteCard.vue';
import CallNotes from './CallNotes.vue';
import CallSummaryCard from './CallSummaryCard.vue';
import CallVariables from './CallVariables.vue';
import { useCallStateText } from './useCallStateText';
import {
  latestSummaryNote,
  parseCallSummaryNote,
  structuredCallSummary,
} from './callSummary';
import {
  CALL_QUICK_TAGS,
  CALL_SHEET_PHASE,
  CALL_SHEET_TAB,
  CALL_SHEET_TABS,
  callSheetPhase,
  callerName,
  callerNumber,
  lineName,
} from './constants';

// The detail of one call, docked to the right of the calls page. Not modal:
// the table stays usable beside it, so it neither locks scrolling nor traps
// focus; Escape and the close button dismiss it.
//
// Its tabs follow the call (CALL_SHEET_TABS): while the AI is on it, the live
// transcript, with the three metrics and quick tags around it; once a human
// has it, what the AI handed over; once it ended, the AI's summary.

const props = defineProps({
  // A calls-list row merged with the live store (see mergeLiveCall), or a
  // live store record when the call is not on the current page.
  call: { type: Object, required: true },
  accountId: { type: Number, required: true },
  currentUserId: { type: Number, default: null },
});

const emit = defineEmits([
  'close',
  'dismissed',
  'followUpResolved',
  'openCall',
]);

const STATUS_BAR_CLASS = {
  [CALL_TONE.RUBY]: 'bg-n-ruby-2 text-n-ruby-12',
  [CALL_TONE.BLUE]: 'bg-n-blue-2 text-n-blue-12',
  [CALL_TONE.SLATE]: 'bg-n-alpha-1 text-n-slate-12',
};
const ENDED_FORMAT = 'MM/dd HH:mm';
const METRIC_PLACEHOLDER = '—';
const TAB_LABEL_KEYS = {
  [CALL_SHEET_TAB.TRANSCRIPT]: 'CALLS_PAGE.SHEET.TABS.TRANSCRIPT',
  [CALL_SHEET_TAB.VARIABLES]: 'CALLS_PAGE.SHEET.TABS.VARIABLES',
  [CALL_SHEET_TAB.NOTES]: 'CALLS_PAGE.SHEET.TABS.NOTES',
  [CALL_SHEET_TAB.HANDOFF]: 'CALLS_PAGE.SHEET.TABS.HANDOFF',
  [CALL_SHEET_TAB.SUMMARY]: 'CALLS_PAGE.SHEET.TABS.SUMMARY',
  [CALL_SHEET_TAB.TECHNICAL]: 'CALLS_PAGE.SHEET.TABS.TECHNICAL',
};

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

// A list row nests the conversation; a live store record carries its id.
const conversationDisplayId = computed(
  () => props.call.conversation?.displayId ?? props.call.conversationId ?? null
);

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
    return [
      stateDetail(props.call, state.value),
      joinDisabledReasonKey && t(joinDisabledReasonKey),
    ]
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
const takeOverLabel = computed(() =>
  t(state.value.joinLabelKey || 'CONVERSATION.VOICE_CALL.TAKE_OVER_CALL')
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

// --- Notes and the AI's summary ---------------------------------------------

// The sheet owns the notes: the summary, the quick tags and the notes tab all
// read and write the same list.
const callNotes = reactive(useCallNotes(conversationDisplayId));
const phase = computed(() => callSheetPhase(state.value));

const summaryNote = computed(() => latestSummaryNote(callNotes.notes));
const parsedSummaryNote = computed(() =>
  summaryNote.value ? parseCallSummaryNote(summaryNote.value.content) : null
);
// The bridge's note is what Pathors writes today; the call's structured
// `summary` stands in when a backend sends that instead.
const summary = computed(() => {
  if (parsedSummaryNote.value) return parsedSummaryNote.value;
  return props.call.summary
    ? structuredCallSummary(props.call.summary, t)
    : null;
});
// Once a human has the call or it ended, the sheet shows the summary note as
// the summary, so the notes leave it out rather than repeat it; while the AI
// is on the call nothing shows it, so it stays a note.
const listedNotes = computed(() => {
  const shownId =
    phase.value !== CALL_SHEET_PHASE.LIVE && parsedSummaryNote.value
      ? summaryNote.value.id
      : null;
  return callNotes.notes.filter(note => note.id !== shownId);
});
const hasVariables = computed(
  () => Object.keys(props.call.variables || {}).length > 0
);
const latestNote = computed(() => listedNotes.value.at(-1) || null);
const technicalFields = computed(
  () => parsedSummaryNote.value?.technical || []
);

const addQuickTag = async key => {
  const saved = await callNotes.create(
    t('CALLS_PAGE.SHEET.QUICK_TAGS.NOTE', {
      tag: t(`CALLS_PAGE.SHEET.QUICK_TAGS.${key}`),
      time: formatDuration(elapsedSeconds.value),
    })
  );
  if (!saved) useAlert(t('CALLS_PAGE.SHEET.NOTES.SAVE_FAILED'));
};

// --- Metrics -------------------------------------------------------------------

// When the call left the AI: the human's join, or the connected transfer.
const handedOffAtMs = computed(() =>
  state.value.key === CALL_STATE.HUMAN
    ? toEpochMs(props.call.acceptedAt)
    : toEpochMs(live.value.attention?.transfer?.at)
);
// The AI's turn counters stop once it is off the call; the clock does not, so
// a handed-off call shows the time up to the hand-off.
const metricSeconds = computed(() => {
  if (phase.value === CALL_SHEET_PHASE.ENDED) return props.call.durationSeconds;
  if (
    phase.value === CALL_SHEET_PHASE.HANDED_OFF &&
    handedOffAtMs.value &&
    startedAtMs.value
  ) {
    return callElapsedSeconds(startedAtMs.value, handedOffAtMs.value);
  }
  return elapsedSeconds.value;
});

const metrics = computed(() => {
  const { DURATION_SECONDS, TURNS, INTERRUPTIONS } = PATHORS_ALERT_THRESHOLDS;
  const { turns, interruptions } = live.value;
  const seconds = metricSeconds.value;
  return [
    {
      key: 'duration',
      label: t(
        phase.value === CALL_SHEET_PHASE.HANDED_OFF
          ? 'CALLS_PAGE.SHEET.METRIC_DURATION_AT_HANDOFF'
          : 'CALLS_PAGE.SHEET.METRIC_DURATION'
      ),
      value: formatDuration(seconds) || METRIC_PLACEHOLDER,
      limit: formatDuration(DURATION_SECONDS),
      isOver: seconds > DURATION_SECONDS,
    },
    {
      key: 'turns',
      label: t('CALLS_PAGE.SHEET.METRIC_TURNS'),
      value: turns ?? METRIC_PLACEHOLDER,
      limit: TURNS,
      isOver: turns > TURNS,
    },
    {
      key: 'interruptions',
      label: t('CALLS_PAGE.SHEET.METRIC_INTERRUPTIONS'),
      value: interruptions ?? METRIC_PLACEHOLDER,
      limit: INTERRUPTIONS,
      isOver: interruptions > INTERRUPTIONS,
    },
  ];
});
const metricsLabel = computed(() =>
  t(
    phase.value === CALL_SHEET_PHASE.HANDED_OFF
      ? 'CALLS_PAGE.SHEET.METRICS_AT_HANDOFF'
      : 'CALLS_PAGE.SHEET.METRICS'
  )
);

// --- Tabs ----------------------------------------------------------------------

const tabIds = computed(() => CALL_SHEET_TABS[phase.value]);
// The agent's pick, until the call moves on (or another call opens): then the
// new phase's first tab.
const pickedTab = ref(null);
watch([phase, () => props.call.id], () => {
  pickedTab.value = null;
});
const activeTab = computed(() =>
  tabIds.value.includes(pickedTab.value) ? pickedTab.value : tabIds.value[0]
);
const tabs = computed(() =>
  tabIds.value.map(id => ({
    id,
    label: t(
      id === CALL_SHEET_TAB.TRANSCRIPT && phase.value === CALL_SHEET_PHASE.LIVE
        ? 'CALLS_PAGE.SHEET.TABS.LIVE_TRANSCRIPT'
        : TAB_LABEL_KEYS[id]
    ),
    count: id === CALL_SHEET_TAB.NOTES ? listedNotes.value.length : 0,
  }))
);
const activeTabIndex = computed(() => tabIds.value.indexOf(activeTab.value));
const pickTab = tab => {
  pickedTab.value = tab.id;
};

// --- Lifecycle -------------------------------------------------------------------

// The attention alerts leave out the call the agent is already looking at.
watch(
  () => props.call.id,
  id => liveCallsStore.setOpenCallId(id),
  { immediate: true }
);

const onKeydown = event => {
  if (event.key !== 'Escape') return;
  // A dialog or the contact popover on top handles its own Escape.
  if (document.querySelector('dialog[open], [data-popover-content]')) return;
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
    class="absolute inset-y-0 end-0 z-20 flex flex-col w-full max-w-[40rem] overflow-hidden border-s shadow-lg bg-n-surface-1 border-n-strong"
    :aria-label="title"
    data-test-id="call-detail-sheet"
  >
    <header
      class="flex items-start gap-3 px-5 py-4 border-b shrink-0 border-n-strong"
    >
      <div class="flex flex-col flex-1 min-w-0 gap-0.5">
        <CallContactPopover
          :call="call"
          :account-id="accountId"
          :title="title"
          @open-call="emit('openCall', $event)"
        />
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

    <section
      class="flex flex-wrap items-center gap-x-4 gap-y-2 px-5 py-3 border-b shrink-0 border-n-strong"
      :class="STATUS_BAR_CLASS[statusTone]"
      data-test-id="call-status-bar"
      :data-state="state.key"
    >
      <div class="flex flex-col grow min-w-0 gap-0.5 basis-48">
        <span class="text-sm font-medium truncate">{{ statusTitle }}</span>
        <p v-if="statusDetail" class="text-sm text-n-slate-11">
          {{ statusDetail }}
        </p>
      </div>
      <div
        v-if="showTakeOver || showDismiss || isInThisCall || isFollowUp"
        class="flex flex-wrap items-center gap-2"
      >
        <Button
          v-if="showTakeOver"
          :label="takeOverLabel"
          icon="i-lucide-phone"
          size="md"
          variant="solid"
          :color="isNeedsHuman ? 'ruby' : 'blue'"
          :disabled="isTakeOverDisabled"
          :is-loading="session.isJoining.value"
          data-test-id="call-take-over"
          @click="takeOver"
        />
        <Button
          v-if="showDismiss"
          :label="t('CALLS_PAGE.ATTENTION.DISMISS')"
          size="md"
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
            size="md"
            color="teal"
            @click="session.enableAudio"
          />
          <Button
            :label="t('CONVERSATION.VOICE_CALL.HANGUP_CALL')"
            icon="i-lucide-phone-off"
            size="md"
            variant="solid"
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
          size="md"
          color="ruby"
          :is-loading="isResolvingFollowUp"
          :disabled="isResolvingFollowUp"
          data-test-id="call-resolve-follow-up"
          @click="resolveFollowUp"
        />
      </div>
    </section>

    <div
      v-if="phase !== CALL_SHEET_PHASE.ENDED"
      class="px-5 py-3 border-b shrink-0 border-n-strong"
    >
      <CallMetrics :metrics="metrics" :label="metricsLabel" />
    </div>

    <nav
      class="px-5 py-2.5 overflow-x-auto border-b shrink-0 border-n-strong"
      :aria-label="t('CALLS_PAGE.SHEET.TABS.LABEL')"
      data-test-id="call-tabs"
    >
      <TabBar
        :tabs="tabs"
        :initial-active-tab="activeTabIndex"
        @tab-changed="pickTab"
      />
    </nav>

    <div
      v-if="activeTab === CALL_SHEET_TAB.TRANSCRIPT"
      class="flex flex-col flex-1 min-h-0"
      data-test-id="call-tab-transcript"
    >
      <section
        v-if="phase === CALL_SHEET_PHASE.ENDED && call.recordingUrl"
        class="flex flex-col gap-2 px-5 pt-4 shrink-0"
      >
        <h3 class="text-sm font-medium text-n-slate-12">
          {{ t('CALLS_PAGE.SHEET.RECORDING') }}
        </h3>
        <AudioPlayer
          :src="call.recordingUrl"
          :fallback-duration="call.durationSeconds || 0"
        />
      </section>
      <CallTranscript
        :key="call.id"
        :entries="live.transcript || []"
        :seq="live.seq || 0"
        :is-live="isLive"
        class="flex-1"
      />
    </div>

    <div
      v-else
      class="flex flex-col flex-1 min-h-0 gap-6 px-5 py-4 overflow-y-auto"
      :data-test-id="`call-tab-${activeTab}`"
    >
      <template v-if="activeTab === CALL_SHEET_TAB.SUMMARY">
        <CallMetrics :metrics="metrics" :label="metricsLabel" />
        <CallSummaryCard
          v-if="summary"
          :summary="summary"
          :title="t('CALLS_PAGE.SHEET.SUMMARY')"
        />
        <p v-else class="text-sm text-n-slate-10">
          {{ t('CALLS_PAGE.SHEET.SUMMARY_EMPTY') }}
        </p>
        <CallVariables v-if="hasVariables" :variables="call.variables" />
        <section class="flex flex-col gap-2" data-test-id="call-latest-note">
          <h3 class="text-sm font-medium text-n-slate-12">
            {{ t('CALLS_PAGE.SHEET.LATEST_NOTE') }}
          </h3>
          <CallNoteCard v-if="latestNote" :note="latestNote" />
          <p v-else class="text-sm text-n-slate-10">
            {{ t('CALLS_PAGE.SHEET.NOTES.EMPTY') }}
          </p>
        </section>
      </template>

      <template v-else-if="activeTab === CALL_SHEET_TAB.HANDOFF">
        <p class="text-sm text-n-slate-11">
          {{ t('CALLS_PAGE.SHEET.HANDOFF_HINT') }}
        </p>
        <CallVariables
          :variables="call.variables"
          :empty-text="t('CALLS_PAGE.SHEET.VARIABLES_PENDING')"
        />
        <CallSummaryCard
          v-if="summary"
          :summary="summary"
          :title="t('CALLS_PAGE.SHEET.HANDOFF_SUMMARY')"
        />
      </template>

      <CallVariables
        v-else-if="activeTab === CALL_SHEET_TAB.VARIABLES"
        :variables="call.variables"
        :empty-text="t('CALLS_PAGE.SHEET.VARIABLES_AT_TAKEOVER')"
      />

      <CallNotes
        v-else-if="activeTab === CALL_SHEET_TAB.NOTES"
        :notes="listedNotes"
        :is-loading="callNotes.isLoading"
        :has-load-error="callNotes.hasLoadError"
        :is-saving="callNotes.isSaving"
        :can-write="!!conversationDisplayId"
        :create="callNotes.create"
      />

      <section
        v-else-if="activeTab === CALL_SHEET_TAB.TECHNICAL"
        class="flex flex-col gap-2"
        data-test-id="call-technical"
      >
        <dl
          class="grid grid-cols-[auto_minmax(0,1fr)] gap-x-4 gap-y-1.5 font-mono text-xs"
        >
          <dt class="text-n-slate-11">
            {{ t('CALLS_PAGE.SHEET.TECHNICAL.CALL_ID') }}
          </dt>
          <dd class="break-all text-n-slate-12">
            {{ call.callId || METRIC_PLACEHOLDER }}
          </dd>
        </dl>
        <template v-if="technicalFields.length">
          <h3 class="pt-3 text-sm font-medium text-n-slate-12">
            {{ t('CALLS_PAGE.SHEET.TECHNICAL.AGENT_FIELDS') }}
          </h3>
          <dl
            class="grid grid-cols-[auto_minmax(0,1fr)] gap-x-4 gap-y-1.5 font-mono text-xs"
          >
            <template v-for="field in technicalFields" :key="field.key">
              <dt class="text-n-slate-11">{{ field.key }}</dt>
              <dd class="break-all text-n-slate-12">{{ field.value }}</dd>
            </template>
          </dl>
        </template>
      </section>
    </div>

    <div
      v-if="phase === CALL_SHEET_PHASE.LIVE"
      class="flex flex-wrap items-center gap-2 px-5 py-3 border-t shrink-0 border-n-strong"
      role="group"
      :aria-label="t('CALLS_PAGE.SHEET.QUICK_TAGS.TITLE')"
      data-test-id="call-quick-tags"
    >
      <span class="text-xs text-n-slate-11 me-1">
        {{ t('CALLS_PAGE.SHEET.QUICK_TAGS.TITLE') }}
      </span>
      <Button
        v-for="tag in CALL_QUICK_TAGS"
        :key="tag"
        :label="t(`CALLS_PAGE.SHEET.QUICK_TAGS.${tag}`)"
        size="sm"
        variant="faded"
        color="slate"
        :disabled="!conversationDisplayId || callNotes.isSaving"
        :data-tag="tag"
        @click="addQuickTag(tag)"
      />
    </div>
  </aside>
</template>
