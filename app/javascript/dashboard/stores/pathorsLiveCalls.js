import camelcaseKeys from 'camelcase-keys';
import { defineStore } from 'pinia';
import PathorsCallsAPI from 'dashboard/api/pathorsCalls';
import { CONTENT_TYPES } from 'dashboard/components-next/message/constants';
import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';
import { isLiveCallStatus } from 'dashboard/helper/pathorsLiveCall';
import { MESSAGE_TYPE } from 'shared/constants/messages';

/**
 * Pathors calls that are still on the line, for the calls page, the attention
 * alerts on every page and the voice_call bubble, and what the AI is doing on
 * each of them.
 *
 * - `records`: the calls themselves (camelized `call` shape plus the
 *   conversation, inbox and caller fields the message keeps, and the handling
 *   state: needsAction, followUp, dismissed, acceptedAt, takeoverRequested).
 *   Seeded from GET pathors/calls/active, then kept current by the voice_call
 *   message broadcasts every status change already produces (see
 *   helper/voice.js) and by `pathors_call.live_updated`, which carries
 *   needsAction and the agent on the call.
 * - `liveById`: the per-turn live state (counters, transcript, attention).
 *   Message payloads never carry it, because message events also reach the
 *   contact; it comes only from the active endpoint and the agent-only
 *   `pathors_call.live_updated` broadcast.
 * - `openCallId`: the call open in the calls page sheet, which the attention
 *   alerts leave out — the agent is already looking at it.
 */

// Ended calls stay out even if a fetch that started before the call ended
// resolves after the broadcast that removed it.
const endedCallIds = new Set();
let inflightFetch = null;

// Calls a status broadcast touched while a fetch was in flight. The fetch's
// snapshot predates those broadcasts, so it must neither drop such a call nor
// overwrite its newer fields.
const syncedSinceFetch = new Set();

// Broadcasts are delivered through a job queue and can arrive out of order;
// never let an older turn overwrite a newer one.
const isOlder = (current, incoming) =>
  !!current?.seq && !!incoming?.seq && incoming.seq < current.seq;

// When the AI asked for help or the transfer failed, for ordering the alerts.
const attentionAt = (record, live) =>
  live?.attention?.takeoverRequest?.at ??
  live?.attention?.transfer?.at ??
  (record.startedAt ? Date.parse(record.startedAt) : 0);

export const usePathorsLiveCallsStore = defineStore('pathorsLiveCalls', {
  state: () => ({
    records: [],
    liveById: {},
    hasLoaded: false,
    openCallId: null,
  }),

  getters: {
    // Changes whenever a call starts or ends, asks for a human or gets one —
    // what moves a call between the calls page sections and the sidebar
    // badges — and not on every AI turn.
    handlingSignature: state =>
      state.records
        .map(
          record =>
            `${record.id}:${record.needsAction ? 1 : 0}:${record.acceptedByAgentId ?? ''}`
        )
        .sort()
        .join(','),

    // Live calls a human is needed on that this agent has not muted, most
    // recent request first, each with its live state attached.
    attentionCalls: state =>
      state.records
        .filter(record => record.needsAction && !record.dismissed)
        .map(record => ({ ...record, live: state.liveById[record.id] || null }))
        .sort(
          (a, b) =>
            attentionAt(b, b.live) - attentionAt(a, a.live) || b.id - a.id
        ),

    hasLiveCallInConversation: state => conversationDisplayId =>
      !!conversationDisplayId &&
      state.records.some(
        record => record.conversationId === conversationDisplayId
      ),
  },

  actions: {
    async fetchActive() {
      syncedSinceFetch.clear();
      const { payload } = await PathorsCallsAPI.active();
      const calls = camelcaseKeys(payload, { deep: true }).filter(
        call => !endedCallIds.has(call.id)
      );
      const fetchedIds = new Set(calls.map(call => call.id));
      const existingById = new Map(
        this.records.map(record => [record.id, record])
      );
      const fetched = calls.map(({ live, ...call }) =>
        syncedSinceFetch.has(call.id)
          ? { ...call, ...existingById.get(call.id) }
          : call
      );
      // A call that rang while the request was in flight is not in its payload.
      const addedMeanwhile = this.records.filter(
        record => !fetchedIds.has(record.id) && syncedSinceFetch.has(record.id)
      );
      this.records = [...fetched, ...addedMeanwhile];

      // Whatever else is missing ended while the socket was down, and its
      // ended broadcast never arrived: drop its live state too.
      const keptIds = new Set(this.records.map(record => record.id));
      Object.keys(this.liveById).forEach(id => {
        if (!keptIds.has(Number(id))) delete this.liveById[id];
      });
      calls.forEach(({ id, live }) => this.applyLive(id, live));
      this.hasLoaded = true;
    },

    // For a bubble opened straight onto a live call (deep link, reload) before
    // anything else loaded the list. One request, however many bubbles ask.
    // A failure only means the bubble waits for the next turn's broadcast.
    ensureLoaded() {
      if (this.hasLoaded || inflightFetch) return inflightFetch;
      inflightFetch = this.fetchActive()
        .catch(error => {
          // eslint-disable-next-line no-console
          console.warn(
            '[pathors-live-calls] could not load active calls',
            error
          );
        })
        .finally(() => {
          inflightFetch = null;
        });
      return inflightFetch;
    },

    /**
     * @param {number} callId
     * @param {Object|null|undefined} live camelized live state
     */
    applyLive(callId, live) {
      if (!live || endedCallIds.has(callId)) return;
      if (isOlder(this.liveById[callId], live)) return;
      this.liveById[callId] = live;
    },

    /**
     * @param {{ id: number, live: Object, needs_action?: boolean,
     *   accepted_by_agent_id?: number|null }} data raw `pathors_call.live_updated` payload
     */
    handleLiveUpdated(data) {
      if (!data?.id || !data.live) return;
      const live = camelcaseKeys(data.live, { deep: true });
      if (endedCallIds.has(data.id) || isOlder(this.liveById[data.id], live)) {
        return;
      }
      this.applyLive(data.id, live);

      const record = this.records.find(item => item.id === data.id);
      if (!record) return;
      if ('needs_action' in data) record.needsAction = data.needs_action;
      if ('accepted_by_agent_id' in data) {
        record.acceptedByAgentId = data.accepted_by_agent_id;
      }
    },

    /**
     * "略過": hides the call's alert for this agent at once; the server keeps
     * it muted across tabs and reloads. Reverted, and rethrown for the caller
     * to report, when the request fails.
     * @param {number} callId
     */
    async dismiss(callId) {
      const record = this.records.find(item => item.id === callId);
      const previous = record?.dismissed ?? false;
      if (record) record.dismissed = true;
      try {
        await PathorsCallsAPI.dismiss(callId);
      } catch (error) {
        if (record) record.dismissed = previous;
        throw error;
      }
    },

    /** @param {number|null} callId */
    setOpenCallId(callId) {
      this.openCallId = callId;
    },

    /**
     * @param {Object} message a raw (snake_case) message from the cable or the API
     */
    syncFromMessage(message) {
      const call = message?.call;
      if (message?.content_type !== CONTENT_TYPES.VOICE_CALL) return;
      if (call?.provider !== VOICE_CALL_PROVIDERS.PATHORS) return;

      if (!isLiveCallStatus(call.status)) {
        endedCallIds.add(call.id);
        this.records = this.records.filter(record => record.id !== call.id);
        delete this.liveById[call.id];
        return;
      }
      if (endedCallIds.has(call.id)) return;

      const existing = this.records.find(record => record.id === call.id);
      // Only an incoming call's message is authored by the contact; otherwise
      // keep what the fetch knew and let the row fall back to the number.
      const caller =
        message.message_type === MESSAGE_TYPE.INCOMING ? message.sender : null;
      const next = {
        ...camelcaseKeys(call, { deep: true }),
        messageId: message.id,
        conversationId: message.conversation_id,
        inboxId: message.inbox_id,
        inboxName: existing?.inboxName ?? null,
        contactName: caller?.name ?? existing?.contactName ?? null,
        contactPhoneNumber:
          caller?.phone_number ?? existing?.contactPhoneNumber ?? null,
      };

      if (existing) {
        Object.assign(existing, next);
      } else {
        this.records.push(next);
      }
      syncedSinceFetch.add(call.id);
    },
  },
});

// Test seam: the module-level state would otherwise leak between specs.
export const resetPathorsLiveCallsTracking = () => {
  endedCallIds.clear();
  syncedSinceFetch.clear();
  inflightFetch = null;
};
