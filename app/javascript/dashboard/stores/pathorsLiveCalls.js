import camelcaseKeys from 'camelcase-keys';
import { defineStore } from 'pinia';
import PathorsCallsAPI from 'dashboard/api/pathorsCalls';
import { CONTENT_TYPES } from 'dashboard/components-next/message/constants';
import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';
import { isLiveCallStatus } from 'dashboard/helper/pathorsLiveCall';
import { MESSAGE_TYPE } from 'shared/constants/messages';

/**
 * Pathors calls that are still on the line, for the pinned "AI handling" group
 * at the top of the conversation list. Voice conversations sit in `pending`
 * under the Pathors bot, so the regular list never shows them.
 *
 * Seeded from GET pathors/calls/active, then kept current by the voice_call
 * message broadcasts every call change already produces (see helper/voice.js).
 * Records use the camelized `call` shape plus the conversation, inbox and
 * caller fields that the broadcast keeps on the message.
 */

// Ended calls stay out even if a fetch that started before the call ended
// resolves after the broadcast that removed it.
const endedCallIds = new Set();

const liveCounters = live =>
  live
    ? {
        seq: live.seq,
        turns: live.turns,
        interruptions: live.interruptions,
        transferFailed: live.transferFailed,
      }
    : null;

// Broadcasts are delivered through a job queue and can arrive out of order;
// never let an older turn overwrite a newer one.
const newerLive = (current, incoming) => {
  if (!incoming) return current || null;
  if (current?.seq && incoming.seq && incoming.seq < current.seq) {
    return current;
  }
  return liveCounters(incoming);
};

export const usePathorsLiveCallsStore = defineStore('pathorsLiveCalls', {
  state: () => ({
    records: [],
  }),

  actions: {
    async fetchActive() {
      const { payload } = await PathorsCallsAPI.active();
      this.records = camelcaseKeys(payload, { deep: true }).filter(
        record => !endedCallIds.has(record.id)
      );
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
        return;
      }
      if (endedCallIds.has(call.id)) return;

      const existing = this.records.find(record => record.id === call.id);
      const { live, ...rest } = camelcaseKeys(call, { deep: true });
      // Only an incoming call's message is authored by the contact; otherwise
      // keep what the fetch knew and let the row fall back to the number.
      const caller =
        message.message_type === MESSAGE_TYPE.INCOMING ? message.sender : null;
      const next = {
        ...rest,
        live: newerLive(existing?.live, live),
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
    },
  },
});

// Test seam: the module-level set would otherwise leak between specs.
export const resetPathorsLiveCallsTracking = () => endedCallIds.clear();
