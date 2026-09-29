# The integration's bookkeeping under a contact's additional_attributes.external
# (note ids, conflicts, dismissals), written in SQL so it neither fires
# contact.updated nor races a concurrent save of the contact's other attributes.
# rubocop:disable Rails/SkipsModelValidations
module Crm::Twenty::ExternalStore
  # additional_attributes with an `external` object guaranteed, since
  # jsonb_set does not create missing parents.
  BASE = "COALESCE(additional_attributes, '{}'::jsonb) || " \
         "jsonb_build_object('external', COALESCE(additional_attributes -> 'external', '{}'::jsonb))".freeze

  module_function

  def write(contact_id, key, value)
    Contact.where(id: contact_id).update_all(["additional_attributes = jsonb_set(#{BASE}, ?::text[], ?::jsonb)", "{external,#{key}}", value.to_json])
  end

  # Shallow-merges a hash into the object stored at external.<key>.
  def merge(contact_id, key, hash)
    Contact.where(id: contact_id).update_all([<<~SQL.squish, "{external,#{key}}", "{external,#{key}}", hash.to_json])
      additional_attributes = jsonb_set(#{BASE}, ?::text[], COALESCE(additional_attributes #> ?::text[], '{}'::jsonb) || ?::jsonb)
    SQL
  end

  def delete(contact_id, *path)
    Contact.where(id: contact_id).update_all(['additional_attributes = additional_attributes #- ?::text[]', "{#{['external', *path].join(',')}}"])
  end
end
# rubocop:enable Rails/SkipsModelValidations
