# Twenty's answers to the generic CRM features (see Crm::Providers).
class Crm::Twenty::Provider
  CONFLICTED = "jsonb_array_length(COALESCE(contacts.additional_attributes #> '{external,twenty_conflicts}', '[]'::jsonb)) > 0".freeze

  pattr_initialize :hook

  def pending_conflicts
    hook.account.contacts.where(CONFLICTED).count
  end

  # Contacts Twenty could match (by email, phone or LINE ids), and those already linked.
  def backfill_scope
    hook.account.contacts.where(
      "contacts.email <> '' OR contacts.phone_number <> '' OR contacts.additional_attributes ->> 'social_line_user_id' <> '' OR " \
      "contacts.additional_attributes #>> '{social_profiles,line}' <> '' OR contacts.additional_attributes #>> '{external,twenty_id}' IS NOT NULL"
    )
  end

  def backfill(contact)
    contact.reload
    person_id = Crm::Twenty::Linker.person_id(contact)
    return :refreshed if person_id && refresh(contact, person_id)
    return :linked if linker.person_id_for(contact, create: false)

    Crm::Twenty::Conflicts.new(contact.reload).stored.any? { |conflict| conflict['type'] == 'ambiguous' } ? :ambiguous : :no_match
  end

  def rate_limited?(error)
    error.is_a?(Crm::Twenty::Api::Client::RateLimitError)
  end

  private

  def linker
    @linker ||= Crm::Twenty::ProcessorService.new(hook).linker
  end

  # false when the person is gone from Twenty; the contact is unlinked and matched afresh.
  def refresh(contact, person_id)
    card = linker.card(person_id)
    if card.nil?
      linker.unlink(contact)
      return false
    end

    linker.record_conflicts(contact, Crm::Twenty::Conflicts.new(contact).for_person(card))
    changed = linker.attributes.linked(contact, card) - ['crm_synced_at']
    Crm::SyncLog.record(hook: hook, action: 'attributes_refreshed', contact: contact, details: { fields: changed }) if changed.any?
    true
  end
end
