<script setup>
import { computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useEmitter } from 'dashboard/composables/emitter';
import { useClock } from 'dashboard/composables/useClock';
import { usePathorsLiveCallsStore } from 'dashboard/stores/pathorsLiveCalls';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import {
  callElapsedSeconds,
  getPathorsCallAlerts,
  sortLiveCalls,
} from 'dashboard/helper/pathorsLiveCall';
import PathorsLiveCallRow from './PathorsLiveCallRow.vue';

// Pinned above the conversation list, whatever its status filter or tab: the
// Pathors calls still on the line. Their conversations sit in `pending` under
// the Pathors bot, so without this an agent never sees a call before taking it
// over. Hidden when there are none.

const { t } = useI18n();
const route = useRoute();
const store = usePathorsLiveCallsStore();
const now = useClock();
const getInbox = useMapGetter('inboxes/getInbox');
const getConversationById = useMapGetter('getConversationById');

const fetchActive = async () => {
  try {
    await store.fetchActive();
  } catch (error) {
    // The broadcasts still fill the list in; a failed seed is not worth a toast.
    // eslint-disable-next-line no-console
    console.warn('[pathors-live-calls] could not load active calls', error);
  }
};

onMounted(fetchActive);
// Broadcasts missed while the socket was down include calls that ended.
useEmitter(BUS_EVENTS.WEBSOCKET_RECONNECT_COMPLETED, fetchActive);

const callerName = call => {
  const sender = getConversationById.value(call.conversationId)?.meta?.sender;
  return (
    call.contactName ||
    sender?.name ||
    call.contactPhoneNumber ||
    call.fromNumber ||
    call.toNumber ||
    ''
  );
};

const rows = computed(() => {
  const nowMs = now.value;
  return sortLiveCalls(store.records, nowMs).map(call => {
    const elapsedSeconds = callElapsedSeconds(call.startedAt, nowMs);
    return {
      call,
      elapsedSeconds,
      alerts: getPathorsCallAlerts(call, elapsedSeconds),
      callerName: callerName(call),
      inboxName: call.inboxName || getInbox.value(call.inboxId)?.name || '',
      isSelected:
        String(route.params.conversation_id) === String(call.conversationId),
      to: {
        name: 'inbox_conversation',
        params: {
          accountId: route.params.accountId,
          conversation_id: call.conversationId,
        },
      },
    };
  });
});
</script>

<template>
  <section
    v-show="rows.length"
    class="shrink-0 max-h-[45%] overflow-y-auto border-b bg-n-surface-2 border-n-strong"
    :aria-label="t('CHAT_LIST.PATHORS_LIVE_CALLS.TITLE')"
    data-test-id="pathors-live-calls"
  >
    <h2
      class="flex items-center gap-1.5 px-4 pt-2.5 pb-1.5 text-xs font-medium text-n-slate-11"
    >
      <span class="rounded-full size-1.5 bg-n-teal-9 animate-pulse" />
      {{ t('CHAT_LIST.PATHORS_LIVE_CALLS.HEADER', { count: rows.length }) }}
    </h2>
    <PathorsLiveCallRow
      v-for="row in rows"
      :key="row.call.id"
      :call="row.call"
      :caller-name="row.callerName"
      :inbox-name="row.inboxName"
      :elapsed-seconds="row.elapsedSeconds"
      :alerts="row.alerts"
      :to="row.to"
      :is-selected="row.isSelected"
    />
  </section>
</template>
