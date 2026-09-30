# Applies a person's decision on one conflict (see Crm::Twenty::Conflicts)
# and returns the contact's refreshed sidebar card.
#
#   field             inbox   write the Inbox value into Twenty (a replaced email or phone is kept
#                             as an additional one)
#                     twenty  write the Twenty value into the Inbox contact
#   ambiguous         person  link to the chosen candidate
#                     new     none of them: create a new person
#   duplicate_contact merge   merge the other contact into this one
#   any               dismiss keep things as they are; not raised again unless something changes
class Crm::Twenty::ConflictResolver
  class Error < StandardError; end

  ACTIONS = {
    %w[field inbox] => :write_to_twenty,
    %w[field twenty] => :write_to_inbox,
    %w[ambiguous person] => :link_to_candidate,
    %w[ambiguous new] => :link_to_new_person,
    %w[duplicate_contact merge] => :merge
  }.freeze

  pattr_initialize [:hook!, :contact!]

  # options: field (field conflicts), person_id (ambiguous), other_contact_id (duplicate_contact)
  def perform(type:, choice:, field: nil, **)
    contact.reload
    action = choice == 'dismiss' ? :dismiss : ACTIONS.fetch([type, choice]) { raise Error, t('conflict_not_found') }
    send(action, type: type, field: field, **)
    Crm::SyncLog.record(hook: hook, action: 'conflict_resolved', contact: contact,
                        details: { conflict_type: type, field: field, choice: choice }.compact)
    Crm::Twenty::PersonCardService.new(hook: hook, contact: contact.reload).perform
  rescue Crm::Twenty::Api::Client::RateLimitError
    raise
  rescue Crm::Twenty::Api::Client::ApiError => e
    raise Error, t('resolve_failed', reason: e.message)
  end

  private

  def linker
    @linker ||= Crm::Twenty::ProcessorService.new(hook).linker
  end

  def client
    linker.client
  end

  def person
    @person ||= client.person(Crm::Twenty::Linker.person_id(contact) || raise(Error, t('person_not_found')))
  end

  def write_to_twenty(field:, **)
    linker.link(contact, client.update_person(person['id'], twenty_attributes(field)))
  end

  def twenty_attributes(field)
    identity = Crm::Twenty::PersonMapper.new(contact)
    case field
    when 'name' then { name: identity.name_attributes }
    when 'email' then { emails: emails_with(contact.email) }
    when 'phone' then { phones: phones_with(contact.phone_number) }
    when 'company' then { companyId: company_id(contact.additional_attributes['company_name']) }
    when 'line_id' then { lineId: identity.line_id }
    when 'line_user_id' then { lineUserId: identity.line_user_id }
    else raise Error, t('conflict_not_found')
    end
  end

  def write_to_inbox(field:, **)
    contact.update!(inbox_attributes(field))
    linker.link(contact, person)
  end

  def inbox_attributes(field)
    case field
    when 'name' then { name: Crm::Twenty::PersonMapper.full_name(person) }
    when 'email' then { email: unused(:email, person.dig('emails', 'primaryEmail').downcase) }
    when 'phone' then { phone_number: unused(:phone_number, e164(Crm::Twenty::Conflicts.person_phone(person))) }
    when 'company' then { additional_attributes: contact.additional_attributes.merge('company_name' => person.dig('company', 'name')) }
    when 'line_id' then { additional_attributes: contact.additional_attributes.merge('social_profiles' => social_profiles_with_line_id) }
    when 'line_user_id' then { additional_attributes: contact.additional_attributes.merge('social_line_user_id' => line_user_id) }
    else raise Error, t('conflict_not_found')
    end
  end

  def social_profiles_with_line_id
    line_id = Crm::Twenty::PersonMapper.line_id(person['lineId'])
    raise Error, t('line_id_taken') if line_id.nil? || Crm::Twenty::PersonMapper.with_line_id(other_contacts, line_id).exists?

    (contact.additional_attributes['social_profiles'] || {}).merge('line' => line_id)
  end

  # A LINE User ID is only ever issued by LINE, so anything else was mistyped in Twenty.
  def line_user_id
    line_user_id = person['lineUserId'].to_s.strip
    raise Error, t('invalid_line_user_id') unless line_user_id.match?(Crm::Twenty::PersonMapper::LINE_USER_ID)
    raise Error, t('line_user_id_taken') if Crm::Twenty::PersonMapper.with_line_user_id(other_contacts, line_user_id).exists?

    line_user_id
  end

  def other_contacts
    contact.account.contacts.where.not(id: contact.id)
  end

  def link_to_candidate(person_id:, **)
    linker.link(contact, client.person(person_id) || raise(Error, t('person_not_found')))
  end

  def link_to_new_person(**)
    linker.link(contact, linker.create_person(contact))
  end

  # The Inbox email becomes primary; the one it replaces stays on as an
  # additional email, so the person can still be found by it.
  def emails_with(email)
    previous = [person.dig('emails', 'primaryEmail'), *person.dig('emails', 'additionalEmails')].compact_blank
    { primaryEmail: email, additionalEmails: (previous - [email]).uniq }
  end

  def phones_with(e164)
    phone = Crm::Twenty::PersonMapper.phone(e164)
    previous = person['phones']
    additional = Array(previous['additionalPhones']).select { |entry| entry['number'].present? }
    if previous['primaryPhoneNumber'].present?
      additional << { number: previous['primaryPhoneNumber'], countryCode: previous['primaryPhoneCountryCode'],
                      callingCode: previous['primaryPhoneCallingCode'] }.compact_blank
    end
    { primaryPhoneNumber: phone[:number], primaryPhoneCountryCode: phone[:country], primaryPhoneCallingCode: phone[:calling_code],
      additionalPhones: additional }.compact
  end

  def company_id(name)
    client.find_company_id(name) || client.create_company(name)['id']
  end

  # Email and phone are unique per account; the holder is a duplicate contact to merge first.
  def unused(attribute, value)
    raise Error, t("#{attribute}_taken") if value.blank? || other_contacts.exists?(attribute => value)

    value
  end

  # Twenty holds some older numbers without a usable calling code; the Inbox needs E.164.
  def e164(phone)
    raise Error, t('invalid_phone') unless phone&.start_with?('+')

    phone
  end

  def merge(other_contact_id:, **)
    other = contact.account.contacts.find(other_contact_id)
    ContactMergeAction.new(account: contact.account, base_contact: contact, mergee_contact: other).perform
    contact.reload
    linker.link(contact, linker.linked_person(contact) || linker.resolve_person(contact, create: false))
  end

  def dismiss(type:, field: nil, other_contact_id: nil, **)
    stored = Crm::Twenty::Conflicts.new(contact).stored
    conflict = stored.find do |candidate|
      candidate['type'] == type && (field.nil? || candidate['field'] == field) &&
        (other_contact_id.nil? || candidate.dig('contact', 'id') == other_contact_id.to_i)
    end
    raise Error, t('conflict_not_found') if conflict.nil?

    remember_dismissal(conflict)
    linker.record_conflicts(contact, stored - [conflict])
  end

  def remember_dismissal(conflict)
    key = Crm::Twenty::Conflicts::DISMISSED_KEY
    dismissed = contact.additional_attributes.dig('external', key) || []
    Crm::Twenty::ExternalStore.write(contact.id, key, (dismissed + [Crm::Twenty::Conflicts.fingerprint(conflict)]).uniq)
  end

  def t(key, **)
    I18n.t("errors.twenty.#{key}", **)
  end
end
