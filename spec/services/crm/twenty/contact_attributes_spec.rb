require 'rails_helper'

# How linking, the sidebar card and unlinking keep a contact's CRM attributes
# (Crm::ContactAttributes) and the sync log in step with Twenty.
RSpec.describe Crm::Twenty::ContactAttributes do
  let(:account) { create(:account) }
  let(:hook) { create(:integrations_hook, :twenty, account: account, settings: { 'api_url' => 'https://crm.example.com', 'api_key' => 'key' }) }
  let(:processor) { Crm::Twenty::ProcessorService.new(hook) }
  let(:linker) { processor.linker }
  let(:contact) { create(:contact, account: account, name: 'Anna Tsai', email: 'anna@acme.com') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:person) do
    {
      'id' => 'person-1',
      'name' => { 'firstName' => 'Anna', 'lastName' => 'Tsai' },
      'emails' => { 'primaryEmail' => 'anna@acme.com' },
      'phones' => { 'primaryPhoneNumber' => '912345678', 'primaryPhoneCountryCode' => 'TW', 'primaryPhoneCallingCode' => '+886' },
      'jobTitle' => 'Head of Support',
      'city' => 'Taipei',
      'linkedinLink' => { 'primaryLinkUrl' => '' },
      'company' => { 'id' => 'company-1', 'name' => 'Acme' }
    }
  end
  let(:own_opportunity) do
    { 'id' => 'opp-own', 'name' => 'Pilot', 'stage' => 'NEW', 'updatedAt' => '2026-09-10T00:00:00Z',
      'owner' => { 'name' => { 'firstName' => 'Brandon', 'lastName' => 'Lu' } } }
  end
  let(:company_opportunity) do
    { 'id' => 'opp-company', 'name' => 'Acme voice agent', 'stage' => 'MEETING', 'updatedAt' => '2026-09-20T00:00:00Z',
      'owner' => { 'name' => { 'firstName' => 'Jack', 'lastName' => 'Cheng' } } }
  end
  let(:crm) { contact.reload.custom_attributes.select { |key, _| key.start_with?('crm_') } }

  def stub_twenty(operation, data)
    stub_request(:post, %r{\Ahttps://crm\.example\.com/(graphql|metadata)\z})
      .with { |request| JSON.parse(request.body)['query'].include?(operation) }
      .to_return(status: 200, body: { data: data }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def twenty_request(operation)
    a_request(:post, %r{\Ahttps://crm\.example\.com/(graphql|metadata)\z}).with { |request| JSON.parse(request.body)['query'].include?(operation) }
  end

  before do
    stub_twenty('query Verify', 'workspaceMembers' => { 'totalCount' => 1 })
    stub_twenty('query Objects', 'objects' => { 'edges' => [{ 'node' => { 'nameSingular' => 'opportunity', 'fieldsList' => [
                  { 'name' => 'stage', 'options' => [{ 'value' => 'MEETING', 'label' => '會議', 'color' => 'sky' },
                                                     { 'value' => 'NEW', 'label' => 'New', 'color' => 'red' }] }
                ] } }] })
    stub_twenty('query PersonCard', 'person' => person.merge(
      'pointOfContactForOpportunities' => { 'edges' => [{ 'node' => own_opportunity }] },
      'noteTargets' => { 'totalCount' => 0, 'edges' => [] }
    ))
    stub_twenty('query CompanyOpportunities', 'opportunities' => { 'edges' => [{ 'node' => company_opportunity }] })
    hook
  end

  describe 'linking' do
    it 'writes the person and their most recently updated opportunity onto the contact' do
      stub_twenty('query FindPeople', 'people' => { 'edges' => [{ 'node' => person }] })

      travel_to(Time.zone.parse('2026-09-30T10:42:00Z')) { processor.process('conversation.created', conversation: conversation) }

      expect(crm).to eq(
        'crm_provider' => 'Twenty', 'crm_status' => 'Linked', 'crm_job_title' => 'Head of Support',
        'crm_stage' => '會議', 'crm_opportunity' => 'Acme voice agent', 'crm_owner' => 'Jack Cheng',
        'crm_url' => 'https://crm.example.com/object/person/person-1', 'crm_synced_at' => '2026-09-30T10:42:00Z'
      )
    end

    it 'logs the link with the fields filled on either side' do
      stub_twenty('query FindPeople', 'people' => { 'edges' => [{ 'node' => person }] })

      processor.process('conversation.created', conversation: conversation)

      event = CrmSyncEvent.find_by(action: 'linked')
      expect(event).to have_attributes(contact_id: contact.id, status: 'success', provider: 'twenty')
      expect(event.details).to eq('fields' => %w[phone_number company_name city], 'to_inbox' => %w[phone_number company_name city], 'to_crm' => [])
    end

    it 'reads the card once and serves the sidebar from it' do
      stub_twenty('query FindPeople', 'people' => { 'edges' => [{ 'node' => person }] })
      processor.process('conversation.created', conversation: conversation)

      card = Crm::Twenty::PersonCardService.new(hook: hook, contact: contact.reload).perform

      expect(card[:opportunities].first).to include(name: 'Acme voice agent', owner: 'Jack Cheng')
      expect(twenty_request('query PersonCard')).to have_been_made.once
      expect(CrmSyncEvent.where(action: %w[linked filled_fields]).count).to eq(1)
    end

    it 'marks the contact as needing attention when it disagrees with the person' do
      contact.update!(additional_attributes: { 'company_name' => 'Globex' })
      stub_twenty('query FindPeople', 'people' => { 'edges' => [{ 'node' => person }] })

      processor.process('conversation.created', conversation: conversation)

      expect(crm['crm_status']).to eq('Needs attention')
      expect(CrmSyncEvent.find_by(action: 'conflict_raised').details).to eq('conflict_type' => 'field', 'field' => 'company')
    end

    it 'keeps the link and the person fields when the card cannot be read' do
      stub_twenty('query FindPeople', 'people' => { 'edges' => [{ 'node' => person }] })
      stub_request(:post, 'https://crm.example.com/graphql').with { |request| request.body.include?('query PersonCard') }.to_return(status: 500)

      processor.process('conversation.created', conversation: conversation)

      expect(contact.reload.additional_attributes.dig('external', 'twenty_id')).to eq('person-1')
      expect(crm).to include('crm_status' => 'Linked', 'crm_job_title' => 'Head of Support')
      expect(crm).not_to have_key('crm_stage')
    end
  end

  describe 'contacts that stay unlinked' do
    let(:contact) { create(:contact, account: account, name: '+886912345678', phone_number: '+886912345678') }

    it 'marks one several people match as needing attention' do
      colleague = person.merge('id' => 'person-2', 'emails' => { 'primaryEmail' => 'brandon@acme.com' })
      stub_twenty('query FindPeople', 'people' => { 'edges' => [{ 'node' => person.merge('emails' => {}) }, { 'node' => colleague }] })

      processor.process('conversation.created', conversation: conversation)

      expect(crm).to eq('crm_provider' => 'Twenty', 'crm_status' => 'Needs attention')
      expect(CrmSyncEvent.find_by(action: 'conflict_raised').details).to eq('conflict_type' => 'ambiguous')
    end

    it 'marks one nobody matches as not linked' do
      stub_twenty('query FindPeople', 'people' => { 'edges' => [] })

      processor.process('conversation.created', conversation: conversation)

      expect(crm).to eq('crm_provider' => 'Twenty', 'crm_status' => 'Not linked')
      expect(CrmSyncEvent.count).to eq(0)
    end
  end

  describe 'unlinking' do
    it 'clears everything but the provider and the status' do
      stub_twenty('query FindPeople', 'people' => { 'edges' => [{ 'node' => person }] })
      processor.process('conversation.created', conversation: conversation)

      linker.unlink(contact)

      expect(crm).to eq('crm_provider' => 'Twenty', 'crm_status' => 'Not linked')
    end
  end

  it 'does not echo its own attribute writes back to Twenty' do
    contact.update!(custom_attributes: { 'crm_stage' => 'Meeting' })

    processor.process('contact.updated', contact: contact, changed_attributes: contact.previous_changes)

    expect(twenty_request('query FindPeople')).not_to have_been_made
  end
end
