# Links an Inbox contact to its Twenty person.
#
# The person id lives under additional_attributes.external.twenty_id. A
# contact is matched by email (unique in Twenty) or by any spelling of its
# phone. Several phone matches with no email match is not guessed at: the
# contact stays unlinked and the candidates are raised as a conflict. Linking
# fills each side's blanks from the other and records what they disagree on
# (Crm::Twenty::Conflicts). A new link also queues the contact's notes that
# never reached Twenty, such as those written while it was ambiguous.
class Crm::Twenty::Linker
  include Events::Types

  EXTERNAL_ID = 'twenty_id'.freeze
  NOTES_KEY = 'twenty_notes'.freeze

  attr_reader :hook, :client

  def initialize(hook, client)
    @hook = hook
    @client = client
  end

  def self.person_id(contact)
    contact.additional_attributes&.dig('external', EXTERNAL_ID).presence
  end

  # The linked person's id, linking first (and with create: true, creating
  # the person when nobody matches). nil when the contact stays unlinked.
  def person_id_for(contact, create:)
    contact.reload
    self.class.person_id(contact) || link(contact, resolve_person(contact, create: create))
  end

  def resolve_person(contact, create:)
    return unless identifiable?(contact)

    people = find_people(contact)
    match = best_match(contact, people)
    return match if match
    return flag_ambiguous(contact, people) if people.many?

    create_person(contact) if create
  end

  # The linked person, or nil; one deleted or merged away in Twenty since it
  # was linked is unlinked so the contact is matched afresh.
  def linked_person(contact)
    person_id = self.class.person_id(contact)
    return if person_id.blank?

    client.person(person_id).tap { |person| unlink(contact) if person.nil? }
  end

  # Fills each side's blanks from the other, stores the link and records the
  # conflicts. One contact save, so one contact.updated event, which the next
  # run finds nothing to do for.
  def link(contact, person)
    return if person.nil?

    newly_linked = self.class.person_id(contact) != person['id']
    person = fill_person(contact, person)
    save_contact(contact, person)
    record_conflicts(contact, Crm::Twenty::Conflicts.new(contact).for_person(person))
    queue_unsynced_notes(contact) if newly_linked
    expire_card(person['id'])
    person['id']
  end

  def create_person(contact)
    return unless identifiable?(contact)

    attributes = Crm::Twenty::PersonMapper.new(contact).create_attributes
    client.create_person(attributes.merge(createdBy: actor, companyId: company_id_for(contact)).compact)
  end

  def unlink(contact)
    Crm::Twenty::ExternalStore.delete(contact.id, EXTERNAL_ID)
    Crm::Twenty::ExternalStore.delete(contact.id, Crm::Twenty::Conflicts::KEY)
    contact.reload
  end

  def record_conflicts(contact, conflicts)
    return if conflicts == Crm::Twenty::Conflicts.new(contact).stored

    Crm::Twenty::ExternalStore.write(contact.id, Crm::Twenty::Conflicts::KEY, conflicts)
    contact.reload
  end

  def expire_card(person_id)
    Crm::Twenty::Cache.delete(hook, 'card', person_id) if person_id
  end

  # Twenty keeps a createdBy name as sent; the member id shows the author's
  # avatar when the agent is also a member of the Twenty workspace.
  def actor(user = nil)
    member = user && workspace_member_ids[user.email.to_s.downcase]
    { source: 'API', name: user&.name.presence || brand_name, workspaceMemberId: member }.compact
  end

  private

  def identifiable?(contact)
    contact.email.present? || contact.phone_number.present? || contact.additional_attributes&.dig('social_profiles').present?
  end

  def find_people(contact)
    mapper = Crm::Twenty::PersonMapper.new(contact)
    client.find_people(emails: mapper.lookup_emails, phones: mapper.lookup_phones)
  end

  # Emails are unique in Twenty and phones are not: an email match wins, and
  # a phone settles it only when a single person has that number.
  def best_match(contact, people)
    by_email = people.find { |person| contact.email.present? && person.dig('emails', 'primaryEmail').to_s.downcase == contact.email }
    by_email || (people.first if people.one?)
  end

  def flag_ambiguous(contact, people)
    record_conflicts(contact, [Crm::Twenty::Conflicts.new(contact).ambiguous(people, client)].compact)
    nil
  end

  def save_contact(contact, person)
    changes = Crm::Twenty::PersonMapper.new(contact).contact_updates(person)
    additional = changes.delete(:additional_attributes) || contact.additional_attributes
    external = (additional['external'] || {}).merge(EXTERNAL_ID => person['id'])
    contact.assign_attributes(changes.merge(additional_attributes: additional.merge('external' => external)))
    contact.save! if contact.changed?
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

  def queue_unsynced_notes(contact)
    synced = (contact.additional_attributes&.dig('external', NOTES_KEY) || {}).keys.map(&:to_i)
    contact.notes.where.not(id: synced).find_each { |note| HookJob.perform_later(hook, NOTE_CREATED, note: note) }
  end

  def workspace_member_ids
    @workspace_member_ids ||= Crm::Twenty::Cache.fetch(hook, 'members', ttl: 1.hour) do
      client.workspace_members.to_h { |member| [member['userEmail'].to_s.downcase, member['id']] }
    end
  end

  def brand_name
    ::GlobalConfig.get('BRAND_NAME')['BRAND_NAME'] || 'Chatwoot'
  end
end
