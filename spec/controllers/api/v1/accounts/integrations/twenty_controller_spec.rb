require 'rails_helper'

RSpec.describe 'Twenty Integration API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:graphql_url) { 'https://crm.example.com/graphql' }
  let(:contact) { create(:contact, account: account, name: 'Anna Tsai', email: 'anna@acme.com') }
  let(:path) { "/api/v1/accounts/#{account.id}/integrations/twenty/person" }
  let(:card) do
    {
      'id' => 'person-1',
      'name' => { 'firstName' => 'Anna', 'lastName' => 'Tsai' },
      'emails' => { 'primaryEmail' => 'anna@acme.com' },
      'phones' => { 'primaryPhoneNumber' => '912345678', 'primaryPhoneCallingCode' => '+886' },
      'jobTitle' => 'Head of Support',
      'city' => 'Taipei',
      'linkedinLink' => { 'primaryLinkUrl' => '' },
      'company' => {
        'id' => 'company-1', 'name' => 'Acme', 'domainName' => { 'primaryLinkUrl' => 'acme.com' },
        'opportunities' => { 'edges' => [{ 'node' => { 'id' => 'opp-1', 'name' => 'Acme voice agent', 'stage' => 'MEETING',
                                                       'amount' => { 'amountMicros' => 120_000_000_000, 'currencyCode' => 'TWD' },
                                                       'closeDate' => '2026-10-31T00:00:00Z', 'updatedAt' => '2026-09-01' } }] }
      },
      'pointOfContactForOpportunities' => { 'edges' => [] },
      'noteTargets' => {
        'totalCount' => 2,
        'edges' => [
          { 'node' => { 'note' => { 'id' => 'note-old', 'title' => 'First call', 'createdAt' => '2026-08-01T00:00:00Z',
                                    'bodyV2' => { 'markdown' => 'Intro' }, 'createdBy' => { 'name' => 'n8n' } } } },
          { 'node' => { 'note' => { 'id' => 'note-new', 'title' => '', 'createdAt' => '2026-09-20T00:00:00Z',
                                    'bodyV2' => { 'markdown' => '**Budget** approved, see [deck](https://x.y)' },
                                    'createdBy' => { 'name' => 'Jack Cheng' } } } }
        ]
      }
    }
  end

  def stub_twenty(operation, body)
    stub_request(:post, %r{\Ahttps://crm\.example\.com/(graphql|metadata)\z})
      .with { |request| JSON.parse(request.body)['query'].include?(operation) }
      .to_return(status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  before do
    stub_twenty('query Verify', data: { workspaceMembers: { totalCount: 1 } })
    stub_twenty('query Objects', data: { objects: { edges: [{ node: { nameSingular: 'opportunity', fieldsList: [
                  { name: 'stage', options: [{ value: 'MEETING', label: 'Meeting', color: 'sky' }] }
                ] } }] } })
    create(:integrations_hook, :twenty, account: account)
  end

  describe 'GET /api/v1/accounts/:account_id/integrations/twenty/person' do
    it 'links the contact and returns the person card, newest notes first' do
      stub_twenty('query FindPeople', data: { people: { edges: [{ node: card.except('noteTargets', 'pointOfContactForOpportunities') }] } })
      stub_twenty('query PersonCard', data: { person: card })

      get path, params: { contact_id: contact.id }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['linked']).to be(true)
      expect(body['person']).to include('name' => 'Anna Tsai', 'url' => 'https://crm.example.com/object/person/person-1',
                                        'phone' => '+886912345678', 'job_title' => 'Head of Support')
      expect(body['person']['company']).to include('name' => 'Acme', 'domain' => 'acme.com')
      expect(body['opportunities'].first).to include('stage' => { 'value' => 'MEETING', 'label' => 'Meeting', 'color' => 'sky' },
                                                     'amount' => { 'value' => 120_000.0, 'currency' => 'TWD' },
                                                     'close_date' => '2026-10-31')
      expect(body['notes'].pluck('id')).to eq(%w[note-new note-old])
      expect(body['notes'].first['excerpt']).to eq('Budget approved, see deck')
    end

    it 'remembers the link on the contact' do
      stub_twenty('query FindPeople', data: { people: { edges: [{ node: card.except('noteTargets', 'pointOfContactForOpportunities') }] } })
      stub_twenty('query PersonCard', data: { person: card })

      get path, params: { contact_id: contact.id }, headers: agent.create_new_auth_token, as: :json

      expect(contact.reload.additional_attributes.dig('external', 'twenty_id')).to eq('person-1')
    end

    it 'says the contact is not in Twenty, and remembers that for a while' do
      stub_twenty('query FindPeople', data: { people: { edges: [] } })

      2.times { get path, params: { contact_id: contact.id }, headers: agent.create_new_auth_token, as: :json }

      expect(response.parsed_body).to include('linked' => false, 'can_create' => true, 'person' => nil)
      expect(a_request(:post, graphql_url).with { |request| request.body.include?('FindPeople') }).to have_been_made.once
    end

    it 'answers 502 when Twenty fails' do
      stub_request(:post, graphql_url).with { |request| request.body.include?('FindPeople') }.to_return(status: 500)

      get path, params: { contact_id: contact.id }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:bad_gateway)
      expect(response.parsed_body['error']).to eq('twenty_unavailable')
    end
  end

  describe 'POST /api/v1/accounts/:account_id/integrations/twenty/person' do
    it 'creates the person and returns the card' do
      stub_twenty('query FindPeople', data: { people: { edges: [] } })
      stub_twenty('query Members', data: { workspaceMembers: { edges: [] } })
      stub_twenty('mutation CreatePerson', data: { createPerson: card.except('noteTargets', 'pointOfContactForOpportunities') })
      stub_twenty('query PersonCard', data: { person: card })

      post path, params: { contact_id: contact.id }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['linked']).to be(true)
      expect(contact.reload.additional_attributes.dig('external', 'twenty_id')).to eq('person-1')
    end

    it 'refuses a contact Twenty could never match' do
      anonymous = create(:contact, account: account, email: nil, phone_number: nil)

      post path, params: { contact_id: anonymous.id }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
