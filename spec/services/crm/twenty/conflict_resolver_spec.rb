require 'rails_helper'

RSpec.describe Crm::Twenty::ConflictResolver do
  let(:account) { create(:account) }
  let(:hook) { create(:integrations_hook, :twenty, account: account) }
  let(:graphql_url) { 'https://crm.example.com/graphql' }
  let(:contact) do
    create(:contact, account: account, name: 'Anna Tsai', email: 'anna@acme.com', phone_number: '+886912345678',
                     additional_attributes: { 'external' => { 'twenty_id' => 'person-1' } })
  end
  let(:person) do
    {
      'id' => 'person-1',
      'name' => { 'firstName' => 'Anna', 'lastName' => 'Tsai' },
      'emails' => { 'primaryEmail' => 'a.tsai@acme.com', 'additionalEmails' => [] },
      'phones' => { 'primaryPhoneNumber' => '912345678', 'primaryPhoneCallingCode' => '+886', 'additionalPhones' => [] },
      'company' => nil
    }
  end
  let(:resolver) { described_class.new(hook: hook, contact: contact) }

  def stub_twenty(operation, data)
    stub_request(:post, graphql_url)
      .with { |request| JSON.parse(request.body)['query'].include?(operation) }
      .to_return(status: 200, body: { data: data }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def twenty_request(operation)
    a_request(:post, graphql_url).with { |request| JSON.parse(request.body)['query'].include?(operation) }
  end

  def stored_conflicts
    contact.reload.additional_attributes.dig('external', 'twenty_conflicts')
  end

  before do
    stub_twenty('query Verify', 'workspaceMembers' => { 'totalCount' => 1 })
    stub_twenty('query Person(', 'person' => person)
    stub_twenty('query PersonCard', 'person' => person.merge('noteTargets' => { 'edges' => [] }))
    stub_twenty('query Objects', 'objects' => { 'edges' => [] })
    hook
  end

  describe 'a field conflict' do
    it 'writes the Inbox email into Twenty and keeps the old one as an additional email' do
      stub_twenty('mutation UpdatePerson', 'updatePerson' => person.merge('emails' => { 'primaryEmail' => 'anna@acme.com' }))

      resolver.perform(type: 'field', choice: 'inbox', field: 'email')

      expect(twenty_request('mutation UpdatePerson').with do |request|
        JSON.parse(request.body).dig('variables', 'data', 'emails') ==
          { 'primaryEmail' => 'anna@acme.com', 'additionalEmails' => ['a.tsai@acme.com'] }
      end).to have_been_made
    end

    it 'writes the Twenty email into the contact' do
      result = resolver.perform(type: 'field', choice: 'twenty', field: 'email')

      expect(contact.reload.email).to eq('a.tsai@acme.com')
      expect(result[:conflicts]).to eq([])
    end

    it 'refuses an email another contact already has' do
      create(:contact, account: account, email: 'a.tsai@acme.com')

      expect { resolver.perform(type: 'field', choice: 'twenty', field: 'email') }
        .to raise_error(described_class::Error, /Merge the two contacts first/)
    end

    it 'keeps both values when dismissed and does not raise it again' do
      Crm::Twenty::PersonCardService.new(hook: hook, contact: contact).perform
      expect(stored_conflicts.pluck('field')).to eq(['email'])

      result = resolver.perform(type: 'field', choice: 'dismiss', field: 'email')

      expect(result[:conflicts]).to eq([])
      expect(contact.reload.email).to eq('anna@acme.com')
      expect(contact.additional_attributes.dig('external', 'twenty_dismissed').size).to eq(1)
    end
  end

  describe 'an ambiguous match' do
    let(:contact) { create(:contact, account: account, name: '+886227001234', phone_number: '+886227001234') }

    it 'links the chosen candidate' do
      stub_twenty('query FindPeople', 'people' => { 'edges' => [] })

      resolver.perform(type: 'ambiguous', choice: 'person', person_id: 'person-1')

      expect(contact.reload.additional_attributes.dig('external', 'twenty_id')).to eq('person-1')
    end
  end

  describe 'a duplicate contact' do
    it 'merges the other contact into this one' do
      other = create(:contact, account: account, phone_number: '+886987654321',
                               additional_attributes: { 'external' => { 'twenty_id' => 'person-1' } })
      conversation = create(:conversation, account: account, contact: other)

      resolver.perform(type: 'duplicate_contact', choice: 'merge', other_contact_id: other.id)

      expect(Contact.exists?(other.id)).to be(false)
      expect(conversation.reload.contact_id).to eq(contact.id)
    end
  end
end
