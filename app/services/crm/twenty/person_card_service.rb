# What the conversation sidebar shows for a contact: the linked Twenty person,
# the opportunities they are on (as point of contact or through their
# company) and their latest notes.
#
# Every sidebar open would otherwise be a Twenty request against a rate limit
# shared by the whole workspace, so cards are cached briefly, and so is the
# answer "nobody in Twenty matches this contact". Each card read also
# refreshes the contact's CRM attributes (a no-op while the card is cached).
class Crm::Twenty::PersonCardService
  CARD_TTL = 2.minutes
  MISS_TTL = 10.minutes
  OPPORTUNITY_LIMIT = 5
  NOTE_LIMIT = 5
  EXCERPT_LENGTH = 280

  pattr_initialize [:hook!, :contact!]

  def perform(create: false)
    card = linked_card(create)
    if card.nil? && Crm::Twenty::Linker.person_id(contact)
      # The person was deleted or merged away in Twenty since it was linked.
      linker.unlink(contact)
      card = linked_card(create)
    end
    card ? present(card) : unlinked
  end

  private

  def linker
    @linker ||= Crm::Twenty::ProcessorService.new(hook).linker
  end

  def client
    linker.client
  end

  def linked_card(create)
    person_id = linked_person_id(create)
    linker.card(person_id) if person_id.present?
  end

  def linked_person_id(create)
    return linker.person_id_for(contact, create: true) if create

    stored = Crm::Twenty::Linker.person_id(contact)
    return stored if stored

    return if Crm::Twenty::Cache.read(hook, *miss_key)

    linker.person_id_for(contact, create: false).tap do |person_id|
      Crm::Twenty::Cache.write(hook, *miss_key, value: true, ttl: MISS_TTL) if person_id.blank?
    end
  end

  # Changes with anything the contact could be matched by.
  def miss_key
    identity = Crm::Twenty::PersonMapper.new(contact)
    ['miss', contact.id, Digest::SHA256.hexdigest([contact.email, contact.phone_number, identity.line_user_id, identity.line_id].join('|'))]
  end

  # Its status may have changed since the last sync: a conflict dismissed, or a cached miss.
  def unlinked
    linker.mark_unlinked(contact)
    { linked: false, can_create: Crm::Twenty::PersonMapper.new(contact).matchable?,
      person: nil, opportunities: [], notes: [], notes_count: 0, conflicts: Crm::Twenty::Conflicts.new(contact).stored }
  end

  def present(card)
    notes = Array(card.dig('noteTargets', 'edges')).filter_map { |edge| edge.dig('node', 'note') }
    conflicts = current_conflicts(card)
    linker.attributes.linked(contact, card)
    {
      linked: true,
      can_create: true,
      conflicts: conflicts,
      person: person(card),
      opportunities: opportunities(card).map { |opportunity| present_opportunity(opportunity) },
      notes: notes.sort_by { |note| note['createdAt'].to_s }.reverse.first(NOTE_LIMIT).map { |note| present_note(note) },
      notes_count: card.dig('noteTargets', 'totalCount') || notes.size
    }
  end

  # Twenty may have changed since the last sync; the card is the freshest view of it.
  def current_conflicts(card)
    linker.record_conflicts(contact, Crm::Twenty::Conflicts.new(contact).for_person(card))
    Crm::Twenty::Conflicts.new(contact).stored
  end

  def person(card)
    phone = card.dig('phones', 'primaryPhoneNumber').presence
    {
      id: card['id'],
      url: client.record_url('person', card['id']),
      name: Crm::Twenty::PersonMapper.full_name(card).presence,
      job_title: card['jobTitle'].presence,
      city: card['city'].presence,
      email: card.dig('emails', 'primaryEmail').presence,
      phone: phone && "#{card.dig('phones', 'primaryPhoneCallingCode')}#{phone}",
      linkedin_url: card.dig('linkedinLink', 'primaryLinkUrl').presence,
      line_id: card['lineId'].presence,
      line_user_id: card['lineUserId'].presence,
      company: company(card['company'])
    }
  end

  def company(company)
    return if company.blank?

    { id: company['id'], name: company['name'], domain: company.dig('domainName', 'primaryLinkUrl').presence,
      url: client.record_url('company', company['id']) }
  end

  def opportunities(card)
    Crm::Twenty::ContactAttributes.opportunities(card).first(OPPORTUNITY_LIMIT)
  end

  def present_opportunity(opportunity)
    stage = opportunity['stage']
    {
      id: opportunity['id'],
      name: opportunity['name'],
      url: client.record_url('opportunity', opportunity['id']),
      stage: stage && { value: stage, label: linker.attributes.stage_label(stage), color: stages.dig(stage, 'color') },
      owner: opportunity['owner'] && Crm::Twenty::PersonMapper.full_name(opportunity['owner']).presence,
      amount: amount(opportunity['amount']),
      close_date: opportunity['closeDate']&.first(10)
    }
  end

  def amount(amount)
    return if amount.blank? || amount['amountMicros'].nil? || amount['currencyCode'].blank?

    { value: amount['amountMicros'].to_f / 1_000_000, currency: amount['currencyCode'] }
  end

  def present_note(note)
    {
      id: note['id'],
      url: client.record_url('note', note['id']),
      title: note['title'].presence,
      excerpt: plain_text(note.dig('bodyV2', 'markdown')),
      created_at: note['createdAt'],
      author: note.dig('createdBy', 'name').presence
    }
  end

  def plain_text(markdown)
    text = markdown.to_s.gsub(/!?\[([^\]]*)\]\([^)]*\)/, '\1').gsub(/[#>*_`|]/, '').squish
    text.truncate(EXCERPT_LENGTH).presence
  end

  def stages
    linker.attributes.stages
  end
end
