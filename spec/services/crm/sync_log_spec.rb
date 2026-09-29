require 'rails_helper'

RSpec.describe Crm::SyncLog do
  let(:account) { create(:account) }
  let(:hook) do
    stub_request(:post, 'https://crm.example.com/graphql')
      .to_return(status: 200, body: { data: { workspaceMembers: { totalCount: 1 } } }.to_json, headers: { 'Content-Type' => 'application/json' })
    create(:integrations_hook, :twenty, account: account)
  end
  let(:contact) { create(:contact, account: account) }

  it 'records an event for the hook' do
    described_class.record(hook: hook, action: 'linked', contact: contact, details: { fields: ['email'] })

    event = CrmSyncEvent.last
    expect(event).to have_attributes(account_id: account.id, hook_id: hook.id, provider: 'twenty', contact_id: contact.id,
                                     action: 'linked', status: 'success', message: nil, details: { 'fields' => ['email'] })
  end

  it 'takes a contact id' do
    described_class.record(hook: hook, action: 'failed', status: 'failure', contact: contact.id, message: 'boom')

    expect(CrmSyncEvent.last).to have_attributes(contact_id: contact.id, status: 'failure', message: 'boom')
  end

  it 'never raises, even when the table is missing' do
    allow(CrmSyncEvent).to receive(:create!)
      .and_raise(ActiveRecord::StatementInvalid, 'PG::UndefinedTable: relation "crm_sync_events" does not exist')
    allow(Rails.logger).to receive(:warn)

    expect(described_class.record(hook: hook, action: 'linked')).to be_nil
    expect(Rails.logger).to have_received(:warn).with(/could not record linked/)
  end

  it 'leaves a surrounding transaction usable when the insert fails in the database' do
    contact
    allow(CrmSyncEvent).to receive(:create!) { ActiveRecord::Base.connection.execute('SELECT * FROM crm_sync_events_missing') }

    ActiveRecord::Base.transaction do
      described_class.record(hook: hook, action: 'linked')
      expect(contact.reload).to be_present
    end
  end
end
