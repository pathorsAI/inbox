require 'rails_helper'

RSpec.describe Crm::SyncEventsCleanupJob do
  let(:account) { create(:account) }
  let(:hook) do
    stub_request(:post, 'https://crm.example.com/graphql')
      .to_return(status: 200, body: { data: { workspaceMembers: { totalCount: 1 } } }.to_json, headers: { 'Content-Type' => 'application/json' })
    create(:integrations_hook, :twenty, account: account)
  end

  it 'deletes events older than 90 days' do
    old = CrmSyncEvent.create!(account: account, hook: hook, provider: 'twenty', action: 'linked', status: 'success', created_at: 91.days.ago)
    recent = CrmSyncEvent.create!(account: account, hook: hook, provider: 'twenty', action: 'linked', status: 'success', created_at: 89.days.ago)

    described_class.perform_now

    expect(CrmSyncEvent.pluck(:id)).to eq([recent.id])
    expect(CrmSyncEvent.exists?(old.id)).to be(false)
  end
end
