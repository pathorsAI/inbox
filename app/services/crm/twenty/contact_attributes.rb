# Writes a contact's generic CRM attributes (Crm::ContactAttributes) from
# what Twenty holds: the person card for a linked contact, the stored
# conflicts for its status.
class Crm::Twenty::ContactAttributes
  PROVIDER = 'Twenty'.freeze
  STAGES_TTL = 12.hours

  pattr_initialize :hook, :client

  # The person's own opportunities and their company's, most recently updated first.
  def self.opportunities(card)
    own = Array(card.dig('pointOfContactForOpportunities', 'edges'))
    company = Array(card.dig('company', 'opportunities', 'edges'))
    (own + company).pluck('node').uniq { |opportunity| opportunity['id'] }.sort_by { |opportunity| opportunity['updatedAt'].to_s }.reverse
  end

  # card: Api::Client#person_card as cached by Linker#card. Returns the changed keys.
  def linked(contact, card)
    opportunity = self.class.opportunities(card).first
    Crm::ContactAttributes.write(
      contact,
      **person_values(contact, card),
      stage: stage_label(opportunity&.dig('stage')),
      opportunity: opportunity&.dig('name'),
      owner: opportunity&.dig('owner') && Crm::Twenty::PersonMapper.full_name(opportunity['owner']),
      # Cards cached before fetched_at was added leave it as it is.
      **(card['fetched_at'] ? { synced_at: Time.zone.parse(card['fetched_at']) } : {})
    )
  end

  # When only the person could be read, the opportunity fields are left as they were.
  def linked_person(contact, person)
    Crm::ContactAttributes.write(contact, **person_values(contact, person), synced_at: Time.current)
  end

  def unlinked(contact)
    Crm::ContactAttributes.clear(contact, provider: PROVIDER, status: status(contact, linked: false))
  end

  # { 'MEETING' => { 'label' => 'Meeting', 'color' => 'sky' }, … }
  def stages
    @stages ||= Crm::Twenty::Cache.fetch(hook, 'stages', ttl: STAGES_TTL) { client.opportunity_stages }
  end

  def stage_label(stage)
    return if stage.blank?

    stages.dig(stage, 'label') || stage.humanize
  end

  private

  def person_values(contact, person)
    { provider: PROVIDER, status: status(contact, linked: true), job_title: person['jobTitle'], url: client.record_url('person', person['id']) }
  end

  def status(contact, linked:)
    return :needs_attention if Crm::Twenty::Conflicts.new(contact).stored.any?

    linked ? :linked : :unlinked
  end
end
