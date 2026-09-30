# Where an Inbox contact and Twenty disagree, kept for a person to settle.
#
# Sync only ever fills blanks, so a real disagreement would otherwise pass
# silently. Three kinds are raised:
#   field             both sides hold a different value for name, email, phone, company,
#                     LINE ID (line_id, case-insensitive) or LINE User ID (line_user_id)
#   ambiguous         several Twenty people match the contact's phone and none its email,
#                     so the contact is left unlinked rather than linked to a guess
#   duplicate_contact another Inbox contact is the same Twenty person, or already holds
#                     that person's email, phone, LINE User ID or LINE ID
#
# They live on the contact (additional_attributes.external.twenty_conflicts),
# so the sidebar and the settings list read them without a Twenty request. A
# dismissed conflict is remembered by a fingerprint of what it compared, and
# comes back only when one side changes.
class Crm::Twenty::Conflicts
  KEY = 'twenty_conflicts'.freeze
  DISMISSED_KEY = 'twenty_dismissed'.freeze
  FIELDS = %w[name email phone company line_id line_user_id].freeze
  CANDIDATE_LIMIT = 5
  DUPLICATE_LIMIT = 3

  pattr_initialize :contact

  def self.fingerprint(conflict)
    case conflict['type']
    when 'field' then "field:#{conflict['field']}:#{digest(conflict['inbox'], conflict['twenty'])}"
    when 'ambiguous' then "ambiguous:#{digest(*conflict['candidates'].pluck('id').sort)}"
    when 'duplicate_contact' then "duplicate:#{conflict.dig('contact', 'id')}"
    else raise ArgumentError, "Unknown Twenty conflict type #{conflict['type']}"
    end
  end

  def self.digest(*values)
    Digest::SHA256.hexdigest(values.join('|')).first(16)
  end

  def stored
    external[KEY] || []
  end

  # Conflicts between the contact and the person it is linked to.
  def for_person(person)
    (FIELDS.filter_map { |field| field_conflict(field, person) } + duplicate_contacts(person)).reject { |conflict| dismissed?(conflict) }
  end

  # nil when this exact set of candidates was dismissed before.
  def ambiguous(people, client)
    candidates = people.first(CANDIDATE_LIMIT).map do |person|
      { 'id' => person['id'], 'name' => Crm::Twenty::PersonMapper.full_name(person).presence,
        'email' => person.dig('emails', 'primaryEmail').presence, 'phone' => self.class.person_phone(person),
        'company' => person.dig('company', 'name'), 'url' => client.record_url('person', person['id']) }
    end
    conflict = { 'type' => 'ambiguous', 'candidates' => candidates }
    conflict unless dismissed?(conflict)
  end

  def dismissed?(conflict)
    (external[DISMISSED_KEY] || []).include?(self.class.fingerprint(conflict))
  end

  # The person's primary phone in E.164 when Twenty holds it parseably,
  # otherwise as stored.
  def self.person_phone(person)
    number = person.dig('phones', 'primaryPhoneNumber').to_s.delete('^0-9')
    return if number.blank?

    code = person.dig('phones', 'primaryPhoneCallingCode').to_s.delete('^0-9')
    e164 = "+#{code}#{number}"
    code.present? && TelephoneNumber.parse(e164).valid? ? e164 : number
  end

  private

  def external
    contact.additional_attributes&.dig('external') || {}
  end

  def field_conflict(field, person)
    inbox, twenty = send(:"#{field}_values", person)
    return if inbox.blank? || twenty.blank? || agree?(field, inbox, twenty, person)

    { 'type' => 'field', 'field' => field, 'inbox' => inbox, 'twenty' => twenty }
  end

  # A value Twenty keeps as an additional email or phone is not a disagreement.
  def agree?(field, inbox, twenty, person)
    case field
    when 'name' then same_name?(inbox, twenty)
    when 'email' then twenty_emails(person).include?(inbox)
    when 'phone' then twenty_numbers(person).intersect?(Crm::Twenty::PersonMapper.phone(inbox)[:variants])
    when 'company' then inbox.downcase.squish == twenty.downcase.squish
    when 'line_id' then inbox.casecmp?(twenty)
    when 'line_user_id' then inbox == twenty
    else raise ArgumentError, "Unknown Twenty conflict field #{field}"
    end
  end

  def name_values(person)
    name = Crm::Twenty::PersonMapper.full_name(person)
    [contact.name, name].map { |value| value unless Crm::Twenty::PersonMapper.placeholder_name?(value, contact.email) }
  end

  # "Anna" and "Anna Tsai" are one name written shorter, and 鄭宇傑 beside
  # "Jack Cheng" is the same person's Chinese and English name; neither is a
  # disagreement worth a person's time.
  def same_name?(inbox, twenty)
    a = inbox.downcase.squish
    b = twenty.downcase.squish
    a.include?(b) || b.include?(a) || a.match?(Crm::Twenty::PersonMapper::HAN) != b.match?(Crm::Twenty::PersonMapper::HAN)
  end

  def email_values(person)
    [contact.email, person.dig('emails', 'primaryEmail').presence&.downcase]
  end

  def twenty_emails(person)
    [person.dig('emails', 'primaryEmail'), *person.dig('emails', 'additionalEmails')].compact_blank.map(&:downcase)
  end

  def phone_values(person)
    [contact.phone_number, self.class.person_phone(person)]
  end

  def twenty_numbers(person)
    numbers = [person.dig('phones', 'primaryPhoneNumber')] + Array(person.dig('phones', 'additionalPhones')).filter_map { |phone| phone['number'] }
    numbers.compact_blank.map { |number| number.delete('^0-9+') }
  end

  def company_values(person)
    [contact.additional_attributes&.dig('company_name').presence, person.dig('company', 'name').presence]
  end

  def line_id_values(person)
    [contact.additional_attributes&.dig('social_profiles', 'line'), person['lineId']].map { |value| value.to_s.strip.presence }
  end

  def line_user_id_values(person)
    [contact.additional_attributes&.dig('social_line_user_id'), person['lineUserId']].map { |value| value.to_s.strip.presence }
  end

  def duplicate_contacts(person)
    same_person(person).order(:id).limit(DUPLICATE_LIMIT).map do |other|
      { 'type' => 'duplicate_contact',
        'contact' => { 'id' => other.id, 'name' => other.name, 'email' => other.email, 'phone_number' => other.phone_number } }
    end
  end

  # Other contacts linked to the person, or holding its email, phone or LINE ids.
  def same_person(person)
    others = contact.account.contacts.where.not(id: contact.id)
    email = person.dig('emails', 'primaryEmail').presence&.downcase
    phone = self.class.person_phone(person)
    scopes = [others.where("contacts.additional_attributes #>> '{external,twenty_id}' = ?", person['id'])]
    scopes << others.where(email: email) if email
    scopes << others.where(phone_number: phone) if phone&.start_with?('+')
    (scopes + line_holders(others, person)).reduce(:or)
  end

  def line_holders(others, person)
    line_user_id = person['lineUserId'].to_s.strip.presence
    line_id = Crm::Twenty::PersonMapper.line_id(person['lineId'])
    [(Crm::Twenty::PersonMapper.with_line_user_id(others, line_user_id) if line_user_id),
     (Crm::Twenty::PersonMapper.with_line_id(others, line_id) if line_id)].compact
  end
end
