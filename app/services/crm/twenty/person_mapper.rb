# Maps a Chatwoot contact onto a Twenty person and back.
#
# Neither side is the master record. Each fills only the other's BLANK fields,
# so an edit made in Twenty is never overwritten from here and vice versa. A
# name made of a phone number or an email address counts as blank: voice
# contacts are named after their number on both sides until someone learns the
# real name.
#
# LINE gives two identities: the User ID a LINE inbox learns
# (additional_attributes.social_line_user_id, Twenty lineUserId) and the LINE
# ID people add friends by, typed in by hand (social_profiles.line, Twenty
# lineId). LINE IDs are case-insensitive and written in lower case.
class Crm::Twenty::PersonMapper
  PLACEHOLDER_NAME = /\A[+\d\s\-().]*\z/
  LINKEDIN_URL = %r{\Ahttps?://(?:[a-z]{2,3}\.)?linkedin\.com/}i
  HAN = /\p{Han}/
  LINE_USER_ID = /\AU\h{32}\z/

  # line_fields: the LINE fields the workspace's people have (Api::Client#line_fields);
  # only needed to write to Twenty.
  pattr_initialize :contact, [{ line_fields: [] }]

  # A phone number in the shapes Twenty holds it: the national significant
  # number plus country and calling code, which is what Twenty's own UI writes
  # (`912345678`, TW, +886), and every spelling older imports left behind
  # (`0912345678`, `886912345678`, `+886912345678`) for lookups.
  def self.phone(e164)
    return if e164.blank?

    parsed = TelephoneNumber.parse(e164)
    return { number: e164, variants: [e164, e164.delete_prefix('+')] } unless parsed.valid?

    code = parsed.country.country_code
    number = e164.delete_prefix("+#{code}")
    {
      number: number,
      country: parsed.country.country_id,
      calling_code: "+#{code}",
      variants: [number, parsed.national_number(formatted: false), "#{code}#{number}", "+#{code}#{number}"].uniq
    }
  end

  def self.full_name(person)
    first = person.dig('name', 'firstName').to_s.strip
    last = person.dig('name', 'lastName').to_s.strip
    # Twenty splits 鄭宇傑 into lastName 鄭 and firstName 宇傑; joined the
    # Western way that reads 宇傑 鄭.
    return "#{last}#{first}" if first.match?(HAN) && last.match?(HAN)

    [first, last].compact_blank.join(' ')
  end

  def self.placeholder_name?(name, email = nil)
    name = name.to_s.strip.downcase
    return true if name.match?(PLACEHOLDER_NAME)

    email.present? && [email.downcase, email.downcase.split('@').first].include?(name)
  end

  def self.line_id(value)
    value.to_s.strip.downcase.presence
  end

  # Contacts in the scope holding the LINE User ID or LINE ID.
  def self.with_line_user_id(contacts, line_user_id)
    contacts.where("contacts.additional_attributes ->> 'social_line_user_id' = ?", line_user_id)
  end

  def self.with_line_id(contacts, line_id)
    contacts.where("LOWER(contacts.additional_attributes #>> '{social_profiles,line}') = ?", line_id)
  end

  def line_user_id
    attribute('social_line_user_id')
  end

  def line_id
    self.class.line_id(contact.additional_attributes&.dig('social_profiles', 'line'))
  end

  # Something a Twenty person can be matched by.
  def matchable?
    contact.email.present? || contact.phone_number.present? || line_user_id.present? || line_id.present?
  end

  # The person among those found (Api::Client#find_people) that the contact is.
  # Emails are unique in Twenty and nothing else is: an email match wins, then
  # the one person holding the LINE User ID, then the one holding the LINE ID,
  # and a phone settles it only when a single person has that number.
  def match(people)
    by_email = people.find { |person| contact.email.present? && person.dig('emails', 'primaryEmail').to_s.downcase == contact.email }
    by_email || only(people) { |person| same_line_user_id?(person) } || only(people) { |person| same_line_id?(person) } ||
      (people.first if people.one?)
  end

  def lookup_emails
    [contact.email].compact_blank
  end

  def lookup_phones
    self.class.phone(contact.phone_number)&.dig(:variants) || []
  end

  def create_attributes
    { name: name_attributes, emails: email_attributes, phones: phones_attributes, city: attribute('city'), linkedinLink: linkedin_attributes,
      **line_attributes }.compact
  end

  # Fields the person is missing that the contact can fill in.
  def person_updates(person)
    {
      name: (name_attributes if name_for_person?(person)),
      emails: (email_attributes if person.dig('emails', 'primaryEmail').blank?),
      phones: (phones_attributes if person.dig('phones', 'primaryPhoneNumber').blank?),
      city: (attribute('city') if person['city'].blank?),
      linkedinLink: (linkedin_attributes if person.dig('linkedinLink', 'primaryLinkUrl').blank?),
      **line_attributes.select { |field, _| person[field.to_s].blank? }
    }.compact
  end

  # Contact attributes Twenty can fill in. Email, phone and the LINE ids are
  # skipped when another contact in the account already has them: that is a
  # duplicate contact, and merging it is a person's call.
  def contact_updates(person)
    updates = {}
    name = self.class.full_name(person)
    updates[:name] = name if self.class.placeholder_name?(contact.name, contact.email) && !self.class.placeholder_name?(name)
    updates[:email] = person_email(person) if contact.email.blank?
    updates[:phone_number] = person_phone(person) if contact.phone_number.blank?
    updates.compact.merge(additional_attribute_updates(person))
  end

  # "Anna Tsai" with no last name on the contact splits into first and last
  # name; a Chinese name, written without spaces, stays whole.
  def name_attributes
    name = contact.name.to_s.strip
    return { firstName: name, lastName: contact.last_name.to_s } if contact.last_name.present? || name.match?(HAN) || name.exclude?(' ')

    first, _, last = name.rpartition(' ')
    { firstName: first, lastName: last }
  end

  private

  def attribute(key)
    contact.additional_attributes&.dig(key).presence
  end

  def name_for_person?(person)
    self.class.placeholder_name?(self.class.full_name(person), person.dig('emails', 'primaryEmail')) &&
      !self.class.placeholder_name?(contact.name, contact.email)
  end

  def email_attributes
    { primaryEmail: contact.email } if contact.email.present?
  end

  def phones_attributes
    phone = self.class.phone(contact.phone_number)
    return if phone.nil?

    { primaryPhoneNumber: phone[:number], primaryPhoneCountryCode: phone[:country], primaryPhoneCallingCode: phone[:calling_code] }.compact
  end

  def only(people, &)
    matches = people.select(&)
    matches.first if matches.one?
  end

  def same_line_user_id?(person) = line_user_id.present? && person['lineUserId'] == line_user_id
  def same_line_id?(person) = line_id.present? && self.class.line_id(person['lineId']) == line_id

  def line_attributes
    { lineUserId: line_user_id, lineId: line_id }.select { |field, value| value && line_fields.include?(field.to_s) }
  end

  def linkedin_attributes
    profile = contact.additional_attributes&.dig('social_profiles', 'linkedin').presence
    return if profile.nil?

    url = profile.match?(%r{\Ahttps?://}) ? profile : "https://www.linkedin.com/#{profile.delete_prefix('/')}"
    { primaryLinkUrl: url }
  end

  def person_email(person)
    email = person.dig('emails', 'primaryEmail').presence&.downcase
    email unless email.nil? || contact.account.contacts.exists?(email: email)
  end

  def person_phone(person)
    number = person.dig('phones', 'primaryPhoneNumber').to_s.delete('^0-9')
    code = person.dig('phones', 'primaryPhoneCallingCode').to_s.delete('^0-9')
    return if number.blank? || code.blank?

    e164 = "+#{code}#{number}"
    e164 if TelephoneNumber.parse(e164).valid? && !contact.account.contacts.exists?(phone_number: e164)
  end

  def person_line_user_id(person)
    line_user_id = person['lineUserId'].to_s.strip
    line_user_id if line_user_id.match?(LINE_USER_ID) && !self.class.with_line_user_id(contact.account.contacts, line_user_id).exists?
  end

  def person_line_id(person)
    line_id = self.class.line_id(person['lineId'])
    line_id unless line_id.nil? || self.class.with_line_id(contact.account.contacts, line_id).exists?
  end

  def additional_attribute_updates(person)
    additions = { 'company_name' => person.dig('company', 'name'), 'city' => person['city'] }.compact_blank.reject { |key, _| attribute(key) }
    additions['social_line_user_id'] = person_line_user_id(person) if line_user_id.nil?
    profiles = social_profile_updates(person)
    additions['social_profiles'] = profiles if profiles
    additions.compact!
    return {} if additions.empty?

    { additional_attributes: contact.additional_attributes.merge(additions) }
  end

  # Chatwoot keeps the part after linkedin.com/ ("in/anna"), Twenty the whole URL.
  def social_profile_updates(person)
    url = person.dig('linkedinLink', 'primaryLinkUrl').to_s
    profiles = contact.additional_attributes['social_profiles'] || {}
    additions = {}
    additions['linkedin'] = url.sub(LINKEDIN_URL, '') if url.match?(LINKEDIN_URL) && profiles['linkedin'].blank?
    additions['line'] = person_line_id(person) if profiles['line'].blank?
    additions.compact!
    profiles.merge(additions) if additions.any?
  end
end
