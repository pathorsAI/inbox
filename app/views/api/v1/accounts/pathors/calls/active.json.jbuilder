# Same keys as the `call` a voice_call message broadcast carries, so the
# dashboard folds both into one list, plus what that broadcast keeps on the
# message instead (conversation, inbox, caller). The list only shows the live
# counters, so the transcript window stays out of this payload.
json.payload @calls do |call|
  json.merge! call.push_event_data.except(:live)
  json.live call.live&.except('transcript')
  json.message_id call.message_id
  json.conversation_id call.conversation.display_id
  json.inbox_id call.inbox_id
  json.inbox_name call.inbox.name
  json.contact_name call.contact&.name
  json.contact_phone_number call.contact&.phone_number
end
