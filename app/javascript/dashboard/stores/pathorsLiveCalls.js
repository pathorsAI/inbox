import camelcaseKeys from 'camelcase-keys';
import { defineStore } from 'pinia';
import PathorsCallsAPI from 'dashboard/api/pathorsCalls';
import { CONTENT_TYPES } from 'dashboard/components-next/message/constants';
import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';
import { isLiveCallStatus } from 'dashboard/helper/pathorsLiveCall';
import { MESSAGE_TYPE } from 'shared/constants/messages';

/**
 * Pathors calls that are still on the line, for the pinned "AI handling" group
 * at the top of the conversation list, and what the AI is doing on each of
 * them for the voice_call bubble.
 *
 * - `records`: the calls themselves (camelized `call` shape plus the
 *   conversation, inbox and caller fields the message keeps). Seeded from
 *   GET pathors/calls/active, then kept current by the voice_call message
 *   broadcasts every status change already produces (see helper/voice.js).
 * - `liveById`: the per-turn live state (counters and transcript). Message
 *   payloads never carry it, because message events also reach the contact;
 *   it comes only from the active endpoint and the agent-only
 *   `pathors_call.live_updated` broadcast.
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

export const usePathorsLiveCallsStore = defineStore('pathorsLiveCalls', {
  state: () => ({
    records: [],
    liveById: {},
    hasLoaded: false,
  }),

  getters: {
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
     * @param {{ id: number, live: Object }} data raw `pathors_call.live_updated` payload
     */
    handleLiveUpdated(data) {
      if (!data?.id || !data.live) return;
      this.applyLive(data.id, camelcaseKeys(data.live, { deep: true }));
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
