# Keeps Chatwoot contacts linked to Twenty people.
#
# A contact is linked by storing the person id under
# additional_attributes.external.twenty_id. Linking looks the person up by
# email or any spelling of the phone number and never creates one on its own:
# only a conversation that got past the mail filters (with "Add new contacts to
# Twenty" on), a contact note, or an agent's click creates people.
#
# Contact notes land on the person as Twenty notes; the Twenty note id per
# Chatwoot note is kept under external.twenty_notes so edits and deletes follow.
class Crm::Twenty::ProcessorService < Crm::BaseProcessorService
  CONTACT_FIELDS = %w[name last_name email phone_number].freeze
  ADDITIONAL_FIELDS = %w[company_name city social_profiles].freeze

  attr_reader :client

  def self.crm_name
    'twenty'
  end

  def initialize(hook)
    super
    @client = Crm::Twenty::Api::Client.new(api_url: hook.settings['api_url'], api_key: hook.settings['api_key'])
  end

  def contact_id_for(event_name, event_data)
    case event_name
    when 'contact.updated' then event_data[:contact].id
    when 'conversation.created', 'conversation.resolved' then event_data[:conversation].contact_id
    when 'note.created', 'note.updated' then event_data[:note].contact_id
    when 'note.deleted' then event_data[:note_data][:contact_id]
    else raise ArgumentError, "Twenty does not handle #{event_name}"
    end
  end

  def process(event_name, event_data)
    case event_name
    when 'contact.updated' then handle_contact_updated(event_data[:contact], event_data[:changed_attributes])
    when 'conversation.created' then handle_conversation_created(event_data[:conversation])
    when 'conversation.resolved' then handle_conversation_resolved(event_data[:conversation])
    when 'note.created', 'note.updated' then handle_note_saved(event_data[:note])
    when 'note.deleted' then handle_note_deleted(event_data[:note_data])
    else raise ArgumentError, "Twenty does not handle #{event_name}"
    end
  end

  # The linked person's id, linking (and with create: true, creating) the
  # person first when the contact has none. nil when nobody matches.
  def person_id_for(contact, create:)
    contact.reload
    get_external_id(contact) || link(contact, find_person(contact) || (create_person(contact) if create))
  end

  # Forgets a person that no longer exists in Twenty, so the next lookup
  # matches the contact afresh.
  def unlink(contact)
    clear_external_id(contact)
  end

  def handle_contact_updated(contact, changed_attributes)
    return unless relevant_change?(changed_attributes)

    contact.reload
    link(contact, linked_person(contact) || find_person(contact) || (create_person(contact) if create_for_contact?(contact)))
  end

  def handle_conversation_created(conversation)
    return if conversation.sender_filtered?

    person_id_for(conversation.contact, create: create_people?)
  end

  def handle_conversation_resolved(conversation)
    return unless loggable?(conversation)

    person_id = person_id_for(conversation.contact, create: create_people?)
    return if person_id.blank?

    note = Crm::Twenty::NoteBuilder.new(@account).conversation_note(conversation)
    note_id = conversation.additional_attributes&.dig(crm_name, 'note_id')
    # A reopened and re-resolved conversation rewrites its note instead of adding another.
    if note_id
      client.update_note(note_id, **note)
    else
      store_conversation_metadata(conversation, 'note_id' => client.create_person_note(person_id: person_id, created_by: actor, **note))
    end
    expire_card(person_id)
  end

  def handle_note_saved(note)
    person_id = person_id_for(note.contact, create: true)
    return if person_id.blank?

    content = Crm::Twenty::NoteBuilder.new(@account).contact_note(note)
    note_id = note_ids(note.contact)[note.id.to_s]
    if note_id
      client.update_note(note_id, **content)
    else
      store_note_id(note.contact_id, note.id, client.create_person_note(person_id: person_id, created_by: actor(note.user), **content))
    end
    expire_card(person_id)
  end

  def handle_note_deleted(note_data)
    contact = @account.contacts.find_by(id: note_data[:contact_id])
    note_id = contact && note_ids(contact)[note_data[:id].to_s]
    return if note_id.blank?

    client.delete_note(note_id)
    forget_note_id(contact.id, note_data[:id])
    expire_card(get_external_id(contact))
  end

  private

  def create_people?
    @hook.settings['create_people'].present?
  end

  # A contact that picks up an email or phone after its conversation started
  # (a widget visitor leaving their address) is created then, on the same terms.
  def create_for_contact?(contact)
    create_people? && contact.conversations.where("conversations.additional_attributes->>'filtered' IS NULL").exists?
  end

  # Calls are skipped: the Pathors platform logs them to Twenty itself.
  def loggable?(conversation)
    @hook.settings['log_conversations'].present? && !conversation.sender_filtered? &&
      !conversation.inbox.voice? && !Call.exists?(conversation_id: conversation.id) &&
      conversation.messages.exists?(message_type: %i[incoming outgoing])
  end

  # The linked person, or nil; one deleted or merged away in Twenty since it
  # was linked is unlinked so the contact is matched afresh.
  def linked_person(contact)
    person_id = get_external_id(contact)
    return if person_id.blank?

    client.person(person_id).tap { |person| unlink(contact) if person.nil? }
  end

  def relevant_change?(changed_attributes)
    return true if changed_attributes.blank?
    return true if changed_attributes.keys.intersect?(CONTACT_FIELDS)

    before, after = changed_attributes['additional_attributes']
    before.to_h.slice(*ADDITIONAL_FIELDS) != after.to_h.slice(*ADDITIONAL_FIELDS)
  end

  def find_person(contact)
    mapper = Crm::Twenty::PersonMapper.new(contact)
    return unless identifiable_contact?(contact)

    people = client.find_people(emails: mapper.lookup_emails, phones: mapper.lookup_phones)
    # Emails are unique in Twenty and phones are not: an email match wins.
    people.find { |person| person.dig('emails', 'primaryEmail').present? && person.dig('emails', 'primaryEmail') == contact.email } ||
      people.first
  end

  def create_person(contact)
    return unless identifiable_contact?(contact)

    attributes = Crm::Twenty::PersonMapper.new(contact).create_attributes
    company_id = company_id_for(contact)
    client.create_person(attributes.merge(createdBy: actor, companyId: company_id).compact)
  end

  # Fills each side's blanks from the other and stores the link. One contact
  # save, so one contact.updated event, which the next run finds nothing to do for.
  def link(contact, person)
    return if person.nil?

    person = fill_person(contact, person)
    changes = Crm::Twenty::PersonMapper.new(contact).contact_updates(person)
    additional = changes.delete(:additional_attributes) || contact.additional_attributes
    external = (additional['external'] || {}).merge("#{crm_name}_id" => person['id'])
    contact.assign_attributes(changes.merge(additional_attributes: additional.merge('external' => external)))
    contact.save! if contact.changed?
    expire_card(person['id'])
    person['id']
  end

  def fill_person(contact, person)
    updates = Crm::Twenty::PersonMapper.new(contact).person_updates(person)
    updates[:companyId] = company_id_for(contact) if person['company'].blank?
    updates.compact!
    updates.present? ? client.update_person(person['id'], updates) : person
  end

  def company_id_for(contact)
    name = contact.additional_attributes&.dig('company_name').presence
    client.find_company_id(name) if name
  end

  # Twenty keeps a createdBy name as sent; the member id makes the note show
  # its author's avatar when that agent is also a Twenty workspace member.
  def actor(user = nil)
    member = user && workspace_member_ids[user.email.to_s.downcase]
    { source: 'API', name: user&.name.presence || brand_name, workspaceMemberId: member }.compact
  end

  def workspace_member_ids
    @workspace_member_ids ||= Crm::Twenty::Cache.fetch(@hook, 'members', ttl: 1.hour) do
      client.workspace_members.to_h { |member| [member['userEmail'].to_s.downcase, member['id']] }
    end
  end

  def note_ids(contact)
    contact.reload.additional_attributes&.dig('external', "#{crm_name}_notes") || {}
  end

  # Written in SQL so the note bookkeeping neither fires contact.updated nor
  # races a concurrent save of the contact's other attributes.
  # rubocop:disable Rails/SkipsModelValidations
  def store_note_id(contact_id, note_id, twenty_note_id)
    Contact.where(id: contact_id).update_all([<<~SQL.squish, { note_id.to_s => twenty_note_id }.to_json])
      additional_attributes = jsonb_set(additional_attributes, '{external,#{crm_name}_notes}',
        COALESCE(additional_attributes #> '{external,#{crm_name}_notes}', '{}'::jsonb) || ?::jsonb)
    SQL
  end

  def forget_note_id(contact_id, note_id)
    path = "{external,#{crm_name}_notes,#{note_id.to_i}}"
    Contact.where(id: contact_id).update_all(['additional_attributes = additional_attributes #- ?::text[]', path])
  end
  # rubocop:enable Rails/SkipsModelValidations

  def expire_card(person_id)
    Crm::Twenty::Cache.delete(@hook, 'card', person_id) if person_id
  end

  def brand_name
    ::GlobalConfig.get('BRAND_NAME')['BRAND_NAME'] || 'Chatwoot'
  end
end
