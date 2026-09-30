require 'rails_helper'

RSpec.describe Crm::Twenty::ProcessorService do
  let(:account) { create(:account) }
  let(:settings) do
    { 'api_url' => 'https://crm.example.com', 'api_key' => 'twenty-api-key', 'create_people' => true, 'log_conversations' => true }
  end
  let(:hook) { create(:integrations_hook, :twenty, account: account, settings: settings) }
  let(:service) { described_class.new(hook) }
  let(:graphql_url) { 'https://crm.example.com/graphql' }
  # The workspace's person fields beyond the standard ones (read from the metadata API).
  let(:custom_person_fields) { [] }
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

  # Every Twenty call is a POST to /graphql (or /metadata); stubs tell them apart by operation name.
  def stub_twenty(operation, data)
    stub_request(:post, %r{\Ahttps://crm\.example\.com/(graphql|metadata)\z})
      .with { |request| JSON.parse(request.body)['query'].include?(operation) }
      .to_return(status: 200, body: { data: data }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def twenty_request(operation)
    a_request(:post, graphql_url).with { |request| JSON.parse(request.body)['query'].include?(operation) }
  end

  before do
    stub_twenty('query Verify', 'workspaceMembers' => { 'totalCount' => 1 })
    stub_twenty('query Members', 'workspaceMembers' => { 'edges' => [] })
    # Linking reads the person card once for the contact's CRM attributes.
    stub_twenty('query PersonCard', 'person' => person.merge('pointOfContactForOpportunities' => { 'edges' => [] }))
    stub_twenty('query CompanyOpportunities', 'opportunities' => { 'edges' => [] })
    stub_twenty('query Objects', 'objects' => { 'edges' => [{ 'node' => {
                  'nameSingular' => 'person',
                  'fieldsList' => %w[id name emails phones].concat(custom_person_fields).map { |name| { 'name' => name, 'isActive' => true } }
                } }] })
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

  describe 'LINE identities' do
    let(:custom_person_fields) { %w[lineUserId lineId] }
    let(:line_user_id) { "U#{'4af49806' * 4}" }
    # A contact a LINE inbox created: named after the LINE display name, known by its User ID only.
    let(:contact) { create(:contact, account: account, name: 'Anna Tsai', additional_attributes: { 'social_line_user_id' => line_user_id }) }
    let(:line_person) do
      { 'id' => 'person-line', 'name' => { 'firstName' => 'Anna', 'lastName' => 'Tsai' }, 'emails' => { 'primaryEmail' => '' },
        'phones' => { 'primaryPhoneNumber' => '' }, 'city' => '', 'linkedinLink' => { 'primaryLinkUrl' => '' }, 'company' => nil,
        'lineUserId' => line_user_id, 'lineId' => nil }
    end

    def find_people_request
      a_request(:post, graphql_url).with { |request| request.body.include?('query FindPeople') }
    end

    def find_people_filter
      filters = []
      expect(find_people_request.with do |request|
        filters << JSON.parse(request.body).dig('variables', 'filter', 'or') if request.body.include?('FindPeople')
      end).to have_been_made
      filters.last
    end

    context 'when the workspace has no LINE fields' do
      let(:custom_person_fields) { [] }

      it 'never names them in a query, and reads the workspace fields once' do
        contact.update!(phone_number: '+886912345678')
        stub_twenty('query FindPeople', 'people' => { 'edges' => [{ 'node' => person }] })
        stub_twenty('query Person(', 'person' => person)

        service.process('conversation.created', conversation: conversation)
        described_class.new(hook).client.person('person-1')

        expect(a_request(:post, graphql_url).with { |request| request.body.include?('lineUserId') || request.body.include?('lineId') })
          .not_to have_been_made
        expect(find_people_filter.flat_map(&:keys)).to eq(['phones'])
        expect(a_request(:post, 'https://crm.example.com/metadata')).to have_been_made.once
      end
    end

    it 'looks people up by LINE User ID and LINE ID and reads both fields back' do
      contact.update!(additional_attributes: contact.additional_attributes.merge('social_profiles' => { 'line' => 'Anna_Tsai' }))
      stub_twenty('query FindPeople', 'people' => { 'edges' => [{ 'node' => line_person }] })
      stub_twenty('mutation UpdatePerson', 'updatePerson' => line_person.merge('lineId' => 'anna_tsai'))

      service.process('conversation.created', conversation: conversation)

      expect(find_people_filter).to eq([{ 'lineUserId' => { 'eq' => line_user_id } }, { 'lineId' => { 'ilike' => 'anna\\_tsai' } }])
      expect(find_people_request.with { |request| request.body.include?('FindPeople') && request.body.include?('lineUserId lineId') })
        .to have_been_made
      expect(contact.reload.additional_attributes.dig('external', 'twenty_id')).to eq('person-line')
    end

    it 'links by LINE ID whatever its case, ahead of a phone match' do
      contact.update!(phone_number: '+886912345678', additional_attributes: { 'social_profiles' => { 'line' => 'Anna_Tsai' } })
      by_phone = person.merge('lineUserId' => nil, 'lineId' => nil)
      by_line_id = line_person.merge('lineUserId' => nil, 'lineId' => 'ANNA_tsai', 'phones' => { 'primaryPhoneNumber' => '' })
      stub_twenty('query FindPeople', 'people' => { 'edges' => [{ 'node' => by_phone }, { 'node' => by_line_id }] })
      stub_twenty('mutation UpdatePerson', 'updatePerson' => by_line_id)

      service.process('conversation.created', conversation: conversation)

      expect(contact.reload.additional_attributes.dig('external', 'twenty_id')).to eq('person-line')
    end

    it 'prefers an email match to a LINE User ID match' do
      contact.update!(email: 'jack@acme.com')
      by_email = person.merge('lineUserId' => nil, 'lineId' => nil)
      stub_twenty('query FindPeople', 'people' => { 'edges' => [{ 'node' => line_person }, { 'node' => by_email }] })
      stub_twenty('mutation UpdatePerson', 'updatePerson' => person)

      service.process('conversation.created', conversation: conversation)

      expect(contact.reload.additional_attributes.dig('external', 'twenty_id')).to eq('person-1')
      expect(contact.additional_attributes['external']['twenty_conflicts']).to be_blank
    end

    it 'prefers a LINE User ID match to a LINE ID match' do
      contact.update!(additional_attributes: contact.additional_attributes.merge('social_profiles' => { 'line' => 'anna' }))
      by_line_id = person.merge('id' => 'person-2', 'lineUserId' => nil, 'lineId' => 'anna')
      stub_twenty('query FindPeople', 'people' => { 'edges' => [{ 'node' => by_line_id }, { 'node' => line_person }] })
      stub_twenty('mutation UpdatePerson', 'updatePerson' => line_person)

      service.process('conversation.created', conversation: conversation)

      expect(contact.reload.additional_attributes.dig('external', 'twenty_id')).to eq('person-line')
    end

    it 'creates a LINE-only contact as a person named after their LINE display name' do
      stub_twenty('query FindPeople', 'people' => { 'edges' => [] })
      stub_twenty('mutation CreatePerson', 'createPerson' => line_person)

      service.process('conversation.created', conversation: conversation)

      expect(twenty_request('mutation CreatePerson').with do |request|
        request.body.include?('CreatePerson') && JSON.parse(request.body).dig('variables', 'data').slice('name', 'lineUserId', 'lineId', 'emails') ==
          { 'name' => { 'firstName' => 'Anna', 'lastName' => 'Tsai' }, 'lineUserId' => line_user_id }
      end).to have_been_made
      expect(contact.reload.additional_attributes.dig('external', 'twenty_id')).to eq('person-line')
    end

    it 'fills each LINE id the other side is missing and logs them as line_id and line_user_id' do
      contact.update!(additional_attributes: { 'social_profiles' => { 'line' => 'Anna_Tsai' }, 'external' => { 'twenty_id' => 'person-line' } })
      stub_twenty('query Person(', 'person' => line_person)
      stub_twenty('mutation UpdatePerson', 'updatePerson' => line_person.merge('lineId' => 'anna_tsai'))

      service.process('contact.updated', contact: contact, changed_attributes: {})

      expect(twenty_request('mutation UpdatePerson').with do |request|
        JSON.parse(request.body).dig('variables', 'data') == { 'lineId' => 'anna_tsai' }
      end).to have_been_made
      expect(contact.reload.additional_attributes['social_line_user_id']).to eq(line_user_id)
      expect(CrmSyncEvent.find_by(action: 'filled_fields').details)
        .to eq('fields' => %w[line_user_id line_id], 'to_inbox' => ['line_user_id'], 'to_crm' => ['line_id'])
    end

    it 'does not copy a LINE User ID another contact already has' do
      contact.update!(additional_attributes: { 'social_profiles' => { 'line' => 'anna_tsai' }, 'external' => { 'twenty_id' => 'person-line' } })
      other = create(:contact, account: account, name: 'Anna (LINE)', additional_attributes: { 'social_line_user_id' => line_user_id })
      stub_twenty('query Person(', 'person' => line_person.merge('lineId' => 'anna_tsai'))

      service.process('contact.updated', contact: contact, changed_attributes: {})

      contact.reload
      expect(contact.additional_attributes).not_to have_key('social_line_user_id')
      expect(contact.additional_attributes.dig('external', 'twenty_conflicts')).to eq(
        [{ 'type' => 'duplicate_contact', 'contact' => { 'id' => other.id, 'name' => 'Anna (LINE)', 'email' => nil, 'phone_number' => nil } }]
      )
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
