<script setup>
import { computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useEmitter } from 'dashboard/composables/emitter';
import { useMapGetter } from 'dashboard/composables/store';
import { useClock } from 'dashboard/composables/useClock';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { attentionHeadline } from 'dashboard/helper/pathorsCallNotification';
import { minutesSince, toEpochMs } from 'dashboard/helper/pathorsCallState';
import { PATHORS_ALERT_LEVEL } from 'dashboard/helper/pathorsLiveCall';
import { usePathorsLiveCallsStore } from 'dashboard/stores/pathorsLiveCalls';
import Button from 'dashboard/components-next/button/Button.vue';
import { useCallStateText } from './useCallStateText';
import { usePathorsCallNotifications } from './usePathorsCallNotifications';
import { callerName, callerNumber, lineName } from './constants';

// The calls in 需要處理, on whatever page the agent is: red ones a human is
// needed on (the AI asked for help, a transfer failed and nobody answered),
// then amber ones the AI still holds but someone should look at (cut off too
// often, too long, too many turns). They stay until someone takes the call,
// it ends, or this agent mutes it (略過: kept server-side for red, for this
// tab only for amber, see dismissAttention).
// The call open in the calls page sheet is left out: the agent is on it.
// The same calls reach the desktop while the dashboard is behind
// (usePathorsCallNotifications).

const MAX_CARDS = 3;
// Relative times only need minute precision.
const CLOCK_TICK_MS = 15_000;

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = usePathorsLiveCallsStore();
const now = useClock(CLOCK_TICK_MS);
const { stateDetail } = useCallStateText();

const accountId = useMapGetter('getCurrentAccountId');
const getInbox = useMapGetter('inboxes/getInbox');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);
const isEnabled = computed(
  () =>
    !!accountId.value &&
    isFeatureEnabledonAccount.value(
      accountId.value,
      FEATURE_FLAGS.CHANNEL_VOICE
    )
);

usePathorsCallNotifications();

const relativeTime = minutes =>
  minutes
    ? t('CALLS_PAGE.ATTENTION.MINUTES_AGO', { minutes })
    : t('CALLS_PAGE.ATTENTION.JUST_NOW');

const calls = computed(() =>
  store.attentionCallsAt(now.value).filter(call => call.id !== store.openCallId)
);

// The calls pages list these calls in their 需要處理 section already, and the
// cards would sit on top of that table and its sheet.
const isOnCallsPage = computed(() =>
  String(route.name || '').startsWith('calls_')
);

const cards = computed(() =>
  (isEnabled.value && !isOnCallsPage.value ? calls.value : [])
    .slice(0, MAX_CARDS)
    .map(call => {
      const state = call.callState;
      const headline = attentionHeadline(state);
      const isAmber = headline.level === PATHORS_ALERT_LEVEL.AMBER;
      return {
        call,
        headline,
        isAmber,
        // A call first seen through its message has no inbox name yet.
        caller: [
          callerName(call) || callerNumber(call),
          lineName(call) || getInbox.value(call.inboxId)?.name,
        ]
          .filter(Boolean)
          .join(' · '),
        detail: isAmber
          ? t(headline.hintKey, headline.hintParams)
          : stateDetail(call, state),
        // An amber call has no moment it asked; how long it has gone on is
        // what makes it amber.
        time: isAmber
          ? t('CALLS_PAGE.ATTENTION.ON_CALL_FOR', {
              minutes: minutesSince(toEpochMs(call.startedAt), now.value),
            })
          : relativeTime(minutesSince(state.at, now.value)),
      };
    })
);

const hiddenCount = computed(() =>
  isEnabled.value ? Math.max(calls.value.length - MAX_CARDS, 0) : 0
);

const goToCall = call =>
  router.push({
    name: 'calls_need',
    params: { accountId: accountId.value },
    query: { call: call.id },
  });

const dismiss = async card => {
  try {
    await store.dismissAttention(card.call.id, card.headline.level);
  } catch {
    useAlert(t('CALLS_PAGE.ATTENTION.DISMISS_FAILED'));
  }
};

const refresh = async () => {
  if (!isEnabled.value) return;
  try {
    await store.fetchActive();
  } catch (error) {
    // The broadcasts still bring new requests in; not worth a toast.
    // eslint-disable-next-line no-console
    console.warn('[pathors-attention] could not load active calls', error);
  }
};

// Nothing else seeds the live store on pages without calls on them, and the
// account (with its feature flags) may resolve after this mounts.
onMounted(() => {
  if (isEnabled.value) store.ensureLoaded();
});
watch(isEnabled, enabled => {
  if (enabled) store.ensureLoaded();
});
// Broadcasts missed while the socket was down include requests and ends.
useEmitter(BUS_EVENTS.WEBSOCKET_RECONNECT_COMPLETED, refresh);
</script>

<template>
  <!-- Always mounted (empty and click-through) so aria-live announces new cards.
       Pinned to the dashboard's main area, not the window, so the app banners
       above it (the call notification prompt among them) stay clickable. -->
  <section
    class="absolute z-50 flex flex-col gap-2 top-3 end-4 w-80 max-w-[calc(100%-2rem)] pointer-events-none"
    :aria-label="t('CALLS_PAGE.ATTENTION.REGION')"
    aria-live="polite"
    data-test-id="pathors-attention-stack"
  >
    <TransitionGroup
      enter-active-class="transition duration-200 ease-out motion-reduce:transition-none"
      enter-from-class="opacity-0 translate-x-2 motion-reduce:translate-x-0"
      leave-active-class="transition duration-150 ease-in motion-reduce:transition-none"
      leave-to-class="opacity-0"
    >
      <article
        v-for="card in cards"
        :key="card.call.id"
        class="flex flex-col gap-1.5 p-3 border-s-[0.1875rem] rounded-lg shadow-lg pointer-events-auto bg-n-solid-2 outline outline-1 -outline-offset-1 outline-n-weak"
        :class="card.isAmber ? 'border-n-amber-9' : 'border-n-ruby-9'"
        data-test-id="pathors-attention-card"
        :data-call-id="card.call.id"
      >
        <div class="flex items-baseline justify-between gap-2">
          <h3
            class="text-sm font-medium"
            :class="card.isAmber ? 'text-n-amber-11' : 'text-n-ruby-11'"
          >
            {{ t(card.headline.labelKey, card.headline.labelParams || {}) }}
          </h3>
          <span class="text-xs text-n-slate-10 shrink-0">
            {{ card.time }}
          </span>
        </div>
        <p v-if="card.caller" class="text-sm truncate text-n-slate-12">
          {{ card.caller }}
        </p>
        <p v-if="card.detail" class="text-xs text-n-slate-11 line-clamp-2">
          {{ card.detail }}
        </p>
        <div class="flex items-center gap-2 mt-1">
          <Button
            :label="t('CALLS_PAGE.ATTENTION.GO_TAKE_OVER')"
            size="xs"
            color="ruby"
            data-test-id="pathors-attention-go"
            @click="goToCall(card.call)"
          />
          <Button
            :label="t('CALLS_PAGE.ATTENTION.DISMISS')"
            size="xs"
            variant="ghost"
            color="slate"
            data-test-id="pathors-attention-dismiss"
            @click="dismiss(card)"
          />
        </div>
      </article>
    </TransitionGroup>
    <p
      v-if="hiddenCount"
      class="px-3 text-xs pointer-events-auto text-end text-n-slate-11"
      data-test-id="pathors-attention-more"
    >
      {{ t('CALLS_PAGE.ATTENTION.MORE', { count: hiddenCount }) }}
    </p>
  </section>
</template>
