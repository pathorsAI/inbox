json.id call.id
json.call_id call.provider_call_id
json.provider call.provider
json.status call.display_status
json.direction call.direction_label
json.duration_seconds call.duration_seconds
json.end_reason call.end_reason
json.started_at call.started_at&.to_i
json.created_at call.created_at.to_i
json.message_id call.message_id
json.recording_url call.recording_url
json.transcript call.transcript
json.from_number call.from_number
json.ended_at call.ended_at
json.accepted_at call.accepted_at
json.accepted_by_agent_name call.accepted_by_agent_name
# The handling state Pathors::CallLifecycleService keeps; agent-only, like the
# rest of this list.
json.needs_action call.needs_action == true
json.follow_up call.follow_up == true
json.outcome call.outcome
json.takeover_requested call.takeover_requested == true
json.dismissed call.dismissed_for?(Current.user)
json.summary call.summary
# Kept after the call ends: the last snapshot holds the only transcript the
# Inbox has for a finished Pathors call, whose platform sends none afterwards.
json.live call.live
# What the AI extracted, from the call's handoff card; nil when no human took
# the call over. Preloaded for the page by CallFinder.
json.variables local_assigns.fetch(:handoff_variables, {})[call.handoff_message_id]

json.conversation do
  json.id call.conversation_id
  json.display_id call.conversation.display_id
  json.status call.conversation.status
end

json.inbox do
  json.id call.inbox_id
  json.name call.inbox.name
  json.channel_type call.inbox.channel_type
  json.medium call.inbox.channel.try(:medium)
end

if call.accepted_by_agent.present?
  json.agent do
    json.id call.accepted_by_agent.id
    json.name call.accepted_by_agent.available_name
    json.avatar call.accepted_by_agent.avatar_url
  end
else
  json.agent nil
end

# A contact deleted after the call leaves the row behind; the list renders a
# fallback name for it rather than dropping the call from the history.
if call.contact.present?
  json.contact do
    json.id call.contact.id
    json.name call.contact.name
    json.phone_number call.contact.phone_number
    json.avatar call.contact.avatar_url
  end
else
  json.contact nil
end
