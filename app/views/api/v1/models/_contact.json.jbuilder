json.additional_attributes resource.additional_attributes
json.availability_status resource.availability_status
json.email resource.email
json.id resource.id
json.name resource.name
json.phone_number resource.phone_number
json.blocked resource.blocked
json.identifier resource.identifier
json.company_id resource.company_id if Current.account&.feature_enabled?('companies')
json.thumbnail resource.avatar_url
json.custom_attributes resource.custom_attributes
json.last_activity_at resource.last_activity_at.to_i if resource[:last_activity_at].present?
json.created_at resource.created_at.to_i if resource[:created_at].present?
# we only want to output contact inbox when its /contacts endpoints
if defined?(with_contact_inboxes) && with_contact_inboxes.present?
  json.contact_inboxes do
    json.array! resource.contact_inboxes do |contact_inbox|
      json.partial! 'api/v1/models/contact_inbox', formats: [:json], resource: contact_inbox
    end
  end
end
# the contacts list (index, search, filter, active) also shows labels and where the contact first came from
if defined?(with_list_fields) && with_list_fields.present?
  json.labels resource.labels.map(&:name)
  source_inbox = resource.contact_inboxes.min_by { |contact_inbox| [contact_inbox.created_at, contact_inbox.id] }&.inbox
  json.source_inbox source_inbox && { id: source_inbox.id, name: source_inbox.name, channel_type: source_inbox.channel_type }
end
