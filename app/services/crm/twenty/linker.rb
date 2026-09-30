# Links an Inbox contact to its Twenty person.
#
# The person id lives under additional_attributes.external.twenty_id. A
# contact is matched by email (unique in Twenty), LINE User ID, LINE ID or any
# spelling of its phone, in that order of trust. Several matches with none
# settled by those is not guessed at: the contact stays unlinked and the
# candidates are raised as a conflict. Linking
# fills each side's blanks from the other and records what they disagree on
# (Crm::Twenty::Conflicts). A new link also queues the contact's notes that
# never reached Twenty, such as those written while it was ambiguous. The
# contact's CRM attributes (Crm::ContactAttributes) follow every link and
# unlink.
class Crm::Twenty::Linker
  include Events::Types

  EXTERNAL_ID = 'twenty_id'.freeze
  NOTES_KEY = 'twenty_notes'.freeze
  # Twenty field → the Inbox field it corresponds to, for the sync log.
  PERSON_FIELD_NAMES = { name: 'name', emails: 'email', phones: 'phone_number', city: 'city', linkedinLink: 'social_profiles',
                         companyId: 'company_name', lineUserId: 'line_user_id', lineId: 'line_id' }.freeze
  # Inbox additional attributes (social profiles one level down) as the sync log names them.
  CONTACT_FIELD_NAMES = { 'social_line_user_id' => 'line_user_id', 'social_profiles.line' => 'line_id',
                          'social_profiles.linkedin' => 'social_profiles' }.freeze

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
    person_id = self.class.person_id(contact) || link(contact, resolve_person(contact, create: create))
    mark_unlinked(contact) if person_id.nil?
    person_id
  end

  def resolve_person(contact, create:)
    return unless identifiable?(contact)

    people = find_people(contact)
    match = Crm::Twenty::PersonMapper.new(contact).match(people)
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
    person, to_crm = fill_person(contact, person)
    to_inbox = save_contact(contact, person)
    record_conflicts(contact, Crm::Twenty::Conflicts.new(contact).for_person(person))
    queue_unsynced_notes(contact) if newly_linked
    expire_card(person['id'])
    refresh_attributes(contact, person)
    log_link(contact, newly_linked, to_inbox, to_crm)
    person['id']
  end

  def create_person(contact)
    return unless identifiable?(contact)

    attributes = mapper(contact).create_attributes
    client.create_person(attributes.merge(createdBy: actor, companyId: company_id_for(contact)).compact).tap do |person|
      Crm::SyncLog.record(hook: hook, action: 'created_person', contact: contact, details: { person_id: person['id'] }) if person
    end
  end

  def unlink(contact)
    Crm::Twenty::ExternalStore.delete(contact.id, EXTERNAL_ID)
    Crm::Twenty::ExternalStore.delete(contact.id, Crm::Twenty::Conflicts::KEY)
    contact.reload
    attributes.unlinked(contact)
  end

  # Status only: a contact nobody in Twenty matches (or several do).
  def mark_unlinked(contact)
    attributes.unlinked(contact) if identifiable?(contact)
  end

  def record_conflicts(contact, conflicts)
    stored = Crm::Twenty::Conflicts.new(contact).stored
    return if conflicts == stored

    Crm::Twenty::ExternalStore.write(contact.id, Crm::Twenty::Conflicts::KEY, conflicts)
    contact.reload
    log_new_conflicts(contact, conflicts, stored)
  end

  # The person with their opportunities and notes, shared with the sidebar
  # card. fetched_at is when it was read from Twenty.
  def card(person_id)
    Crm::Twenty::Cache.fetch(hook, 'card', person_id, ttl: Crm::Twenty::PersonCardService::CARD_TTL) do
      client.person_card(person_id, opportunity_limit: Crm::Twenty::PersonCardService::OPPORTUNITY_LIMIT)
            &.merge('fetched_at' => Time.current.iso8601)
    end
  end

  def attributes
    @attributes ||= Crm::Twenty::ContactAttributes.new(hook, client)
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

  def mapper(contact)
    Crm::Twenty::PersonMapper.new(contact, line_fields: client.line_fields)
  end

  def identifiable?(contact)
    Crm::Twenty::PersonMapper.new(contact).matchable? || contact.additional_attributes&.dig('social_profiles').present?
  end

  def find_people(contact)
    identity = Crm::Twenty::PersonMapper.new(contact)
    client.find_people(emails: identity.lookup_emails, phones: identity.lookup_phones, line_user_id: identity.line_user_id,
                       line_id: identity.line_id)
  end

  def flag_ambiguous(contact, people)
    record_conflicts(contact, [Crm::Twenty::Conflicts.new(contact).ambiguous(people, client)].compact)
    nil
  end

  # Returns the Inbox fields it filled.
  def save_contact(contact, person)
    changes = Crm::Twenty::PersonMapper.new(contact).contact_updates(person)
    additional = changes.delete(:additional_attributes) || contact.additional_attributes
    filled = changes.keys.map(&:to_s) + filled_additional(contact.additional_attributes, additional)
    external = (additional['external'] || {}).merge(EXTERNAL_ID => person['id'])
    contact.assign_attributes(changes.merge(additional_attributes: additional.merge('external' => external)))
    contact.save! if contact.changed?
    filled
  end

  def filled_additional(before, after)
    before = flat_attributes(before)
    flat_attributes(after).reject { |key, value| before[key] == value }.keys.map { |key| CONTACT_FIELD_NAMES.fetch(key, key) }.uniq
  end

  def flat_attributes(attributes)
    profiles = (attributes['social_profiles'] || {}).transform_keys { |profile| "social_profiles.#{profile}" }
    attributes.except('social_profiles').merge(profiles)
  end

  # Returns the person as it now is, and the fields filled on it.
  def fill_person(contact, person)
    updates = mapper(contact).person_updates(person)
    updates[:companyId] = company_id_for(contact) if person['company'].blank?
    updates.compact!
    return [person, []] if updates.blank?

    [client.update_person(person['id'], updates), updates.keys.map { |field| PERSON_FIELD_NAMES.fetch(field) }]
  end

  # The card was just expired, so this reads Twenty afresh (and warms the
  # sidebar's cache). The link stands if that read fails; the opportunity
  # fields catch up on the next card read.
  def refresh_attributes(contact, person)
    fresh = card(person['id'])
    fresh ? attributes.linked(contact, fresh) : attributes.linked_person(contact, person)
  rescue Crm::Twenty::Api::Client::ApiError => e
    Rails.logger.warn("Twenty card read after linking contact #{contact.id} failed: #{e.message}")
    attributes.linked_person(contact, person)
  end

  def log_link(contact, newly_linked, to_inbox, to_crm)
    fields = (to_inbox + to_crm).uniq
    details = fields.any? ? { fields: fields, to_inbox: to_inbox, to_crm: to_crm } : {}
    if newly_linked
      Crm::SyncLog.record(hook: hook, action: 'linked', contact: contact, details: details)
    elsif fields.any?
      Crm::SyncLog.record(hook: hook, action: 'filled_fields', contact: contact, details: details)
    end
  end

  def log_new_conflicts(contact, conflicts, stored)
    known = stored.map { |conflict| Crm::Twenty::Conflicts.fingerprint(conflict) }
    conflicts.reject { |conflict| known.include?(Crm::Twenty::Conflicts.fingerprint(conflict)) }.each do |conflict|
      Crm::SyncLog.record(hook: hook, action: 'conflict_raised', contact: contact,
                          details: { conflict_type: conflict['type'], field: conflict['field'] }.compact)
    end
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
