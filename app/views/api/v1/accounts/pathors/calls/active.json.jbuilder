# Same keys as the `call` a voice_call message broadcast carries, so the
# dashboard folds both into one list, plus what that broadcast keeps on the
# message instead (conversation, inbox, caller) and the live state, which only
# this agent-scoped endpoint and the pathors_call.live_updated broadcast carry.
# The transcript is included so a conversation opened mid-call shows it at once.
json.payload @calls do |call|
  json.merge! call.push_event_data
  json.live call.live
  json.message_id call.message_id
  json.conversation_id call.conversation.display_id
  json.inbox_id call.inbox_id
  json.inbox_name call.inbox.name
  json.contact_name call.contact&.name
  json.contact_phone_number call.contact&.phone_number
end
