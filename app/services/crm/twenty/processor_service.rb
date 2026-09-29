# Keeps Inbox contacts and their notes in step with Twenty (linking itself is
# Crm::Twenty::Linker).
#
# People are never created just because a contact exists: only a conversation
# that got past the mail filters (with "Add new contacts to Twenty" on), a
# contact note, or an agent creates one. Contact notes land on the person as
# Twenty notes, and the Twenty note id per note is kept under
# external.twenty_notes so edits and deletes follow.
class Crm::Twenty::ProcessorService < Crm::BaseProcessorService
  CONTACT_FIELDS = %w[name last_name email phone_number].freeze
  ADDITIONAL_FIELDS = %w[company_name city social_profiles].freeze

  attr_reader :client, :linker

  def self.crm_name
    'twenty'
  end

  def initialize(hook)
    super
    @client = Crm::Twenty::Api::Client.new(api_url: hook.settings['api_url'], api_key: hook.settings['api_key'])
    @linker = Crm::Twenty::Linker.new(hook, @client)
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

  def handle_contact_updated(contact, changed_attributes)
    return unless relevant_change?(changed_attributes)

    contact.reload
    linker.link(contact, linker.linked_person(contact) || linker.resolve_person(contact, create: create_for_contact?(contact)))
  end

  def handle_conversation_created(conversation)
    return if conversation.sender_filtered?

    linker.person_id_for(conversation.contact, create: create_people?)
  end

  def handle_conversation_resolved(conversation)
    return unless loggable?(conversation)

    person_id = linker.person_id_for(conversation.contact, create: create_people?)
    return if person_id.blank?

    note = Crm::Twenty::NoteBuilder.new(@account).conversation_note(conversation)
    note_id = conversation.additional_attributes&.dig(crm_name, 'note_id')
    # A reopened and re-resolved conversation rewrites its note instead of adding another.
    if note_id
      client.update_note(note_id, **note)
    else
      store_conversation_metadata(conversation, 'note_id' => client.create_person_note(person_id: person_id, created_by: linker.actor, **note))
    end
    linker.expire_card(person_id)
  end

  def handle_note_saved(note)
    person_id = linker.person_id_for(note.contact, create: true)
    return if person_id.blank?

    content = Crm::Twenty::NoteBuilder.new(@account).contact_note(note)
    note_id = note_ids(note.contact)[note.id.to_s]
    if note_id
      client.update_note(note_id, **content)
    else
      twenty_note_id = client.create_person_note(person_id: person_id, created_by: linker.actor(note.user), **content)
      Crm::Twenty::ExternalStore.merge(note.contact_id, Crm::Twenty::Linker::NOTES_KEY, note.id.to_s => twenty_note_id)
    end
    linker.expire_card(person_id)
  end

  def handle_note_deleted(note_data)
    contact = @account.contacts.find_by(id: note_data[:contact_id])
    note_id = contact && note_ids(contact)[note_data[:id].to_s]
    return if note_id.blank?

    client.delete_note(note_id)
    Crm::Twenty::ExternalStore.delete(contact.id, Crm::Twenty::Linker::NOTES_KEY, note_data[:id].to_i)
    linker.expire_card(Crm::Twenty::Linker.person_id(contact))
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

  def relevant_change?(changed_attributes)
    return true if changed_attributes.blank?
    return true if changed_attributes.keys.intersect?(CONTACT_FIELDS)

    before, after = changed_attributes['additional_attributes']
    before.to_h.slice(*ADDITIONAL_FIELDS) != after.to_h.slice(*ADDITIONAL_FIELDS)
  end

  def note_ids(contact)
    contact.reload.additional_attributes&.dig('external', Crm::Twenty::Linker::NOTES_KEY) || {}
  end
end
