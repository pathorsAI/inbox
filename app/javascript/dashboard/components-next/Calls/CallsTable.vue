<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { format, isToday, isYesterday } from 'date-fns';
import { formatDuration } from 'shared/helpers/timeHelper';
import {
  CALL_STATE,
  hasRequestedHelp,
  toEpochMs,
} from 'dashboard/helper/pathorsCallState';
import {
  callElapsedSeconds,
  isLiveCallStatus,
} from 'dashboard/helper/pathorsLiveCall';
import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';
import { BaseTable, BaseTableRow, BaseTableCell } from '../table';
import CallStateChip from './CallStateChip.vue';
import { useCallStateText } from './useCallStateText';
import {
  CALL_TONE_CHIP_CLASS,
  CALL_TONE_STRIPE_CLASS,
  callerName,
  callerNumber,
  lineName,
} from './constants';

const props = defineProps({
  // [{ key: 'need'|'live'|'today'|'yesterday'|'earlier', rows: [{ call, state }] }]
  sections: { type: Array, default: () => [] },
  selectedId: { type: Number, default: null },
  // Epoch ms, ticking, for the live timers.
  now: { type: Number, required: true },
});

const emit = defineEmits(['open']);

const { t } = useI18n();
const { stateDetail } = useCallStateText();

const COLUMN_COUNT = 7;
const TIME_FORMAT = 'HH:mm';
const DATE_TIME_FORMAT = 'MM/dd HH:mm';

const headers = computed(() => [
  t('CALLS_PAGE.TABLE.TIME'),
  t('CALLS_PAGE.TABLE.CALLER'),
  t('CALLS_PAGE.TABLE.LINE'),
  t('CALLS_PAGE.TABLE.STATUS'),
  t('CALLS_PAGE.TABLE.CONTENT'),
  t('CALLS_PAGE.TABLE.LENGTH'),
  t('CALLS_PAGE.TABLE.HANDLER'),
]);

const rows = computed(() => props.sections.flatMap(section => section.rows));

const startedAtMs = call => toEpochMs(call.startedAt ?? call.createdAt);

const timeLabel = call => {
  const startedAt = startedAtMs(call);
  if (!startedAt) return '';
  if (isLiveCallStatus(call.status)) {
    return formatDuration(callElapsedSeconds(startedAt, props.now));
  }
  const date = new Date(startedAt);
  return format(
    date,
    isToday(date) || isYesterday(date) ? TIME_FORMAT : DATE_TIME_FORMAT
  );
};

const lengthLabel = call =>
  isLiveCallStatus(call.status) ? '' : formatDuration(call.durationSeconds);

const handlerLabel = (call, state) => {
  if (state.key === CALL_STATE.HUMAN)
    return t(state.labelKey, state.labelParams);
  if (call.agent?.name) return call.agent.name;
  return call.provider === VOICE_CALL_PROVIDERS.PATHORS
    ? t('CALLS_PAGE.TABLE.HANDLER_AI')
    : '';
};

// Signals the primary state does not already say.
const secondaryChips = (call, state) => [
  // A follow-up's primary chip is 待回電; what happened goes here instead.
  ...(state.key === CALL_STATE.ENDED && call.followUp
    ? [{ key: 'outcome', label: t(state.outcomeKey), tone: 'slate' }]
    : []),
  ...(state.key !== CALL_STATE.REQUESTED && hasRequestedHelp(call)
    ? [
        {
          key: 'requested',
          label: t('CALLS_PAGE.CHIPS.REQUESTED_HELP'),
          tone: 'slate',
        },
      ]
    : []),
];

const displayName = call =>
  callerName(call) ||
  callerNumber(call) ||
  t('CALLS_PAGE.TABLE.UNKNOWN_CALLER');
</script>

<template>
  <div class="w-full min-w-0 overflow-x-auto">
    <BaseTable :headers="headers" :items="rows">
      <template #row>
        <template v-for="section in sections" :key="section.key">
          <tr data-test-id="calls-section">
            <td
              :colspan="COLUMN_COUNT"
              class="pt-5 pb-2 text-xs font-medium text-n-slate-11"
            >
              {{ t(`CALLS_PAGE.SECTIONS.${section.key.toUpperCase()}`) }}
              <span class="tabular-nums text-n-slate-10">
                {{ section.rows.length }}
              </span>
            </td>
          </tr>
          <BaseTableRow
            v-for="{ call, state } in section.rows"
            :key="call.id"
            :item="call"
            class="cursor-pointer hover:bg-n-alpha-1"
            :class="{ 'bg-n-alpha-2': call.id === selectedId }"
            :aria-selected="call.id === selectedId"
            data-test-id="calls-row"
            @click="emit('open', call)"
          >
            <BaseTableCell class="relative ps-3">
              <span
                class="absolute inset-y-1 start-0 w-[0.1875rem] rounded-full"
                :class="CALL_TONE_STRIPE_CLASS[state.tone]"
              />
              <span
                class="inline-flex items-center gap-1.5 whitespace-nowrap tabular-nums"
                :class="
                  isLiveCallStatus(call.status)
                    ? 'text-n-teal-11'
                    : 'text-n-slate-11'
                "
              >
                <span
                  v-if="isLiveCallStatus(call.status)"
                  class="rounded-full size-1.5 bg-current motion-safe:animate-pulse"
                />
                {{ timeLabel(call) }}
              </span>
            </BaseTableCell>
            <BaseTableCell>
              <div class="flex flex-col min-w-0 max-w-48">
                <span class="truncate text-n-slate-12">
                  {{ displayName(call) }}
                </span>
                <span
                  v-if="callerName(call) && callerNumber(call)"
                  class="text-xs truncate tabular-nums text-n-slate-10"
                >
                  {{ callerNumber(call) }}
                </span>
              </div>
            </BaseTableCell>
            <BaseTableCell>
              <span class="block truncate max-w-40">{{ lineName(call) }}</span>
            </BaseTableCell>
            <BaseTableCell>
              <CallStateChip :state="state" />
            </BaseTableCell>
            <BaseTableCell>
              <div class="flex flex-col gap-1 min-w-0 max-w-96">
                <span
                  v-if="stateDetail(call, state)"
                  class="truncate text-n-slate-12"
                  :title="stateDetail(call, state)"
                >
                  {{ stateDetail(call, state) }}
                </span>
                <span
                  v-if="secondaryChips(call, state).length"
                  class="flex flex-wrap gap-1"
                >
                  <span
                    v-for="chip in secondaryChips(call, state)"
                    :key="chip.key"
                    class="px-1.5 rounded-md text-xs leading-5"
                    :class="CALL_TONE_CHIP_CLASS[chip.tone]"
                  >
                    {{ chip.label }}
                  </span>
                </span>
              </div>
            </BaseTableCell>
            <BaseTableCell>
              <span class="whitespace-nowrap tabular-nums">
                {{ lengthLabel(call) }}
              </span>
            </BaseTableCell>
            <BaseTableCell>
              <span class="block truncate max-w-40">
                {{ handlerLabel(call, state) }}
              </span>
            </BaseTableCell>
          </BaseTableRow>
        </template>
      </template>
    </BaseTable>
  </div>
</template>
