require 'rails_helper'

RSpec.describe Crm::Twenty::ProcessorService do
  let(:account) { create(:account) }
  let(:settings) do
    { 'api_url' => 'https://crm.example.com', 'api_key' => 'twenty-api-key', 'create_people' => true, 'log_conversations' => true }
  end
  let(:hook) { create(:integrations_hook, :twenty, account: account, settings: settings) }
  let(:service) { described_class.new(hook) }
  let(:graphql_url) { 'https://crm.example.com/graphql' }
  let(:contact) { create(:contact, account: account, name: '+886912345678', phone_number: '+886912345678') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:person) do
    {
      'id' => 'person-1',
      'name' => { 'firstName' => '宇傑', 'lastName' => '鄭' },
      'emails' => { 'primaryEmail' => 'jack@acme.com' },
      'phones' => { 'primaryPhoneNumber' => '912345678', 'primaryPhoneCountryCode' => 'TW', 'primaryPhoneCallingCode' => '+886' },
      'city' => '',
      'linkedinLink' => { 'primaryLinkUrl' => '' },
      'company' => { 'id' => 'company-1', 'name' => 'Acme' }
    }
  end

  # Every Twenty call is a POST to /graphql; stubs tell them apart by operation name.
  def stub_twenty(operation, data)
    stub_request(:post, graphql_url)
      .with { |request| JSON.parse(request.body)['query'].include?(operation) }
      .to_return(status: 200, body: { data: data }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def twenty_request(operation)
    a_request(:post, graphql_url).with { |request| JSON.parse(request.body)['query'].include?(operation) }
  end

  before do
    stub_twenty('query Verify', 'workspaceMembers' => { 'totalCount' => 1 })
    stub_twenty('query Members', 'workspaceMembers' => { 'edges' => [] })
    hook
  end

  describe 'conversation.created' do
    it 'links the contact to the person matching any spelling of the phone and fills its blanks' do
      stub_twenty('query FindPeople', 'people' => { 'edges' => [{ 'node' => person }] })

      service.process('conversation.created', conversation: conversation)

      contact.reload
      expect(contact.additional_attributes.dig('external', 'twenty_id')).to eq('person-1')
      expect(contact.name).to eq('鄭宇傑')
      expect(contact.email).to eq('jack@acme.com')
      expect(contact.additional_attributes['company_name']).to eq('Acme')
      expect(twenty_request('query FindPeople').with do |request|
        JSON.parse(request.body).dig('variables', 'filter', 'or', 0, 'phones', 'primaryPhoneNumber', 'in') ==
          %w[912345678 0912345678 886912345678 +886912345678]
      end).to have_been_made
      expect(twenty_request('mutation UpdatePerson')).not_to have_been_made
    end

    it 'creates the person when nobody matches' do
      stub_twenty('query FindPeople', 'people' => { 'edges' => [] })
      stub_twenty('mutation CreatePerson', 'createPerson' => person.merge('id' => 'person-new'))

      service.process('conversation.created', conversation: conversation)

      expect(contact.reload.additional_attributes.dig('external', 'twenty_id')).to eq('person-new')
      expect(twenty_request('mutation CreatePerson').with do |request|
        JSON.parse(request.body).dig('variables', 'data', 'phones') ==
          { 'primaryPhoneNumber' => '912345678', 'primaryPhoneCountryCode' => 'TW', 'primaryPhoneCallingCode' => '+886' }
      end).to have_been_made
    end

    it 'does not guess between several people sharing the phone, and asks instead' do
      colleague = person.merge('id' => 'person-2', 'name' => { 'firstName' => 'Brandon', 'lastName' => 'Lu' }, 'emails' => { 'primaryEmail' => '' })
      stub_twenty('query FindPeople', 'people' => { 'edges' => [{ 'node' => person }, { 'node' => colleague }] })

      service.process('conversation.created', conversation: conversation)

      external = contact.reload.additional_attributes['external']
      expect(external).not_to have_key('twenty_id')
      expect(external['twenty_conflicts']).to match([hash_including('type' => 'ambiguous')])
      expect(external['twenty_conflicts'].first['candidates'].pluck('id')).to eq(%w[person-1 person-2])
      expect(twenty_request('mutation CreatePerson')).not_to have_been_made
    end

    it 'only links when adding new contacts is off' do
      hook.update!(settings: settings.merge('create_people' => false))
      stub_twenty('query FindPeople', 'people' => { 'edges' => [] })

      service.process('conversation.created', conversation: conversation)

      expect(twenty_request('mutation CreatePerson')).not_to have_been_made
      expect(contact.reload.additional_attributes['external']).to be_nil
    end

    it 'ignores mail the sender filters parked' do
      conversation.update!(additional_attributes: { 'filtered' => 'newsletter' })

      service.process('conversation.created', conversation: conversation)

      expect(twenty_request('query FindPeople')).not_to have_been_made
    end

    it 'makes no request for a contact that is already linked' do
      contact.update!(additional_attributes: { 'external' => { 'twenty_id' => 'person-1' } })

      service.process('conversation.created', conversation: conversation)

      expect(a_request(:post, graphql_url).with { |request| request.body.exclude?('Verify') }).not_to have_been_made
    end
  end

  describe 'contact.updated' do
    it 'does nothing when only bookkeeping attributes changed' do
      service.process('contact.updated', contact: contact, changed_attributes: { 'last_activity_at' => [nil, Time.current] })

      expect(twenty_request('query FindPeople')).not_to have_been_made
    end

    it 'fills the linked person from an edit to the contact' do
      contact.update!(email: 'jack@acme.com', additional_attributes: { 'external' => { 'twenty_id' => 'person-1' } })
      stub_twenty('query Person(', 'person' => person.merge('emails' => { 'primaryEmail' => '' }, 'city' => 'Taipei'))
      stub_twenty('mutation UpdatePerson', 'updatePerson' => person)

      service.process('contact.updated', contact: contact, changed_attributes: { 'email' => [nil, 'jack@acme.com'] })

      expect(twenty_request('mutation UpdatePerson').with do |request|
        JSON.parse(request.body).dig('variables', 'data') == { 'emails' => { 'primaryEmail' => 'jack@acme.com' } }
      end).to have_been_made
    end
  end

  describe 'contact notes' do
    let(:agent) { create(:user, account: account, name: 'Jack Cheng') }
    let(:note) { create(:note, account: account, contact: contact, user: agent, content: "Wants a demo in October\nBudget approved") }

    before do
      contact.update!(additional_attributes: { 'external' => { 'twenty_id' => 'person-1' } })
      stub_twenty('mutation CreatePersonNote', 'createNote' => { 'id' => 'x' }, 'createNoteTarget' => { 'id' => 'y' })
      stub_twenty('mutation DeleteNote', 'deleteNote' => { 'id' => 'x' })
    end

    it 'copies a new note onto the person, credited to its author' do
      service.process('note.created', note: note)

      expect(twenty_request('mutation CreatePersonNote').with do |request|
        variables = JSON.parse(request.body)['variables']
        variables.dig('note', 'title') == 'Wants a demo in October' &&
          variables.dig('note', 'createdBy') == { 'source' => 'API', 'name' => 'Jack Cheng' } &&
          variables.dig('target', 'targetPersonId') == 'person-1' &&
          variables.dig('target', 'noteId') == variables.dig('note', 'id')
      end).to have_been_made
      expect(contact.reload.additional_attributes.dig('external', 'twenty_notes', note.id.to_s)).to be_present
    end

    it 'deletes the Twenty note when the note is deleted' do
      service.process('note.created', note: note)
      twenty_note_id = contact.reload.additional_attributes.dig('external', 'twenty_notes', note.id.to_s)

      service.process('note.deleted', note_data: { id: note.id, contact_id: contact.id, account_id: account.id })

      expect(twenty_request('mutation DeleteNote').with { |request| JSON.parse(request.body).dig('variables', 'id') == twenty_note_id })
        .to have_been_made
      expect(contact.reload.additional_attributes.dig('external', 'twenty_notes')).to eq({})
      expect(contact.additional_attributes.dig('external', 'twenty_id')).to eq('person-1')
    end
  end

  describe 'conversation.resolved' do
    before do
      contact.update!(additional_attributes: { 'external' => { 'twenty_id' => 'person-1' } })
      create(:message, conversation: conversation, account: account, inbox: conversation.inbox, message_type: :incoming, content: 'Hi')
      stub_twenty('mutation CreatePersonNote', 'createNote' => { 'id' => 'x' }, 'createNoteTarget' => { 'id' => 'y' })
    end

    it 'logs the transcript on the person and remembers the note' do
      service.process('conversation.resolved', conversation: conversation)

      expect(twenty_request('mutation CreatePersonNote').with do |request|
        JSON.parse(request.body).dig('variables', 'note', 'bodyV2', 'markdown').to_s.include?('> Hi')
      end).to have_been_made
      expect(conversation.reload.additional_attributes.dig('twenty', 'note_id')).to be_present
    end

    it 'skips phone calls, which the Pathors platform logs itself' do
      create(:call, conversation: conversation)

      service.process('conversation.resolved', conversation: conversation)

      expect(twenty_request('mutation CreatePersonNote')).not_to have_been_made
    end

    it 'does nothing when conversation logging is off' do
      hook.update!(settings: settings.merge('log_conversations' => false))

      service.process('conversation.resolved', conversation: conversation)

      expect(twenty_request('mutation CreatePersonNote')).not_to have_been_made
    end
  end

  describe 'rate limiting' do
    it 'raises a retryable error when Twenty reports its throttle' do
      stub_request(:post, graphql_url)
        .with { |request| request.body.include?('query FindPeople') }
        .to_return(status: 200, body: { errors: [{ message: 'Limit reached (100 tokens per 60000 ms)' }] }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      expect { service.process('conversation.created', conversation: conversation) }
        .to raise_error(Crm::Twenty::Api::Client::RateLimitError)
    end
  end
end
