require 'rails_helper'

RSpec.describe 'CRM sync API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:hook) do
    stub_request(:post, 'https://crm.example.com/graphql')
      .to_return(status: 200, body: { data: { workspaceMembers: { totalCount: 1 } } }.to_json, headers: { 'Content-Type' => 'application/json' })
    create(:integrations_hook, :twenty, account: account)
  end
  let(:contact) { create(:contact, account: account, name: 'Rea Sagang', email: 'rea@example.com') }
  let(:base_path) { "/api/v1/accounts/#{account.id}/integrations/hooks/#{hook.id}" }

  def event(action, status: 'success', at: Time.current, **attributes)
    CrmSyncEvent.create!(account: account, hook: hook, provider: 'twenty', action: action, status: status, created_at: at, **attributes)
  end

  describe 'GET /api/v1/accounts/:account_id/integrations/hooks/:id/sync_events' do
    let(:path) { "#{base_path}/sync_events" }

    it 'returns the summary and the newest events first' do
      travel_to(Time.zone.parse('2026-09-30T12:00:00Z')) do
        event('linked', at: Time.zone.parse('2026-09-30T10:42:00Z'), contact: contact, details: { fields: ['company_name'] })
        event('failed', status: 'failure', at: 2.hours.ago, message: 'Twenty API error: 500',
                        details: { error_class: 'Crm::Twenty::Api::Client::ApiError' })
        event('rate_limited', status: 'failure', at: 3.hours.ago, message: 'Limit reached')
        event('note_synced', at: 2.days.ago)
        contact.update!(additional_attributes: { 'external' => { 'twenty_conflicts' => [{ 'type' => 'field', 'field' => 'email' }] } })

        get path, headers: admin.create_new_auth_token, as: :json
      end

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['summary']).to eq(
        'last_success_at' => '2026-09-30T10:42:00Z',
        'last_24h' => { 'success' => 1, 'failure' => 1, 'rate_limited' => 1 },
        'pending_conflicts' => 1
      )
      expect(body['events'].pluck('action')).to eq(%w[linked failed rate_limited note_synced])
      expect(body['events'].first).to eq(
        'id' => CrmSyncEvent.find_by(action: 'linked').id, 'action' => 'linked', 'status' => 'success', 'message' => nil,
        'details' => { 'fields' => ['company_name'] }, 'contact' => { 'id' => contact.id, 'name' => 'Rea Sagang' },
        'created_at' => '2026-09-30T10:42:00Z'
      )
      expect(body['meta']).to eq('page' => 1, 'has_more' => false)
    end

    it 'pages by 25 and filters by status' do
      26.times { |index| event('note_synced', at: index.minutes.ago) }
      event('failed', status: 'failure', at: 1.day.ago)

      get path, params: { page: 2 }, headers: admin.create_new_auth_token
      expect(response.parsed_body['events'].size).to eq(2)
      expect(response.parsed_body['meta']).to eq('page' => 2, 'has_more' => false)

      get path, params: { page: 1 }, headers: admin.create_new_auth_token
      expect(response.parsed_body['meta']).to eq('page' => 1, 'has_more' => true)

      get path, params: { status: 'failure' }, headers: admin.create_new_auth_token
      expect(response.parsed_body['events'].pluck('action')).to eq(['failed'])
    end

    it 'rejects an unknown status' do
      get path, params: { status: 'pending' }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'shows only this hook’s events' do
      hook
      other_account = create(:account)
      other = CrmSyncEvent.create!(account: other_account, hook: create(:integrations_hook, :twenty, account: other_account),
                                   provider: 'twenty', action: 'linked', status: 'success')

      get path, headers: admin.create_new_auth_token

      expect(response.parsed_body['events'].pluck('id')).not_to include(other.id)
    end

    it 'is for administrators only' do
      get path, headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end

    it 'is not found for a hook that is not a CRM' do
      slack = create(:integrations_hook, account: account)

      get "/api/v1/accounts/#{account.id}/integrations/hooks/#{slack.id}/sync_events", headers: admin.create_new_auth_token

      expect(response).to have_http_status(:not_found)
    end
  end

  describe '/api/v1/accounts/:account_id/integrations/hooks/:id/crm_backfill' do
    let(:path) { "#{base_path}/crm_backfill" }

    before { create_list(:contact, 2, :with_email, account: account) }

    it 'starts a backfill and reports it running' do
      freeze_time do
        expect { post path, headers: admin.create_new_auth_token }.to have_enqueued_job(Crm::BackfillJob).with(hook)

        expect(response).to have_http_status(:accepted)
        expect(response.parsed_body).to eq(
          'state' => 'running', 'total' => 2, 'processed' => 0, 'linked' => 0, 'refreshed' => 0, 'ambiguous' => 0, 'no_match' => 0,
          'errors' => 0, 'started_at' => Time.current.iso8601, 'finished_at' => nil
        )
      end
    end

    it 'refuses a second run while one is going' do
      post path, headers: admin.create_new_auth_token

      post path, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to eq('error' => 'already_running')
    end

    it 'reports idle before any run, and the progress after' do
      get path, headers: admin.create_new_auth_token
      expect(response.parsed_body).to include('state' => 'idle', 'processed' => 0, 'started_at' => nil)

      progress = Crm::BackfillProgress.new(hook)
      progress.start!(2)
      progress.advance('linked')
      get path, headers: admin.create_new_auth_token
      expect(response.parsed_body).to include('state' => 'running', 'total' => 2, 'processed' => 1, 'linked' => 1)

      progress.finish!
      get path, headers: admin.create_new_auth_token
      expect(response.parsed_body).to include('state' => 'finished', 'processed' => 1)
      expect(response.parsed_body['finished_at']).to be_present
    end

    it 'is for administrators only' do
      post path, headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
      expect(Crm::BackfillProgress.new(hook)).not_to be_running
    end
  end
end
