require 'rails_helper'

RSpec.describe 'Pathors Connection API', type: :request do
  let(:account) { create(:account, name: 'Acme Support') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:connect_secret) { 'test_connect_secret' }
  let(:organization_id) { '3f1c2d4e-5a6b-4c7d-8e9f-0a1b2c3d4e5f' }
  let(:other_organization_id) { '9e8d7c6b-5a4f-4e3d-2c1b-0a9f8e7d6c5b' }
  let(:bot_url) { 'https://backend.pathors.test/project/project-uuid-1/integration/chatwoot/callback' }

  def decoded_connect_token(authorize_url)
    token = CGI.parse(URI.parse(authorize_url).query)['connect_token'].first
    JWT.decode(token, connect_secret, true, algorithm: 'HS256').first
  end

  before do
    allow(GlobalConfigService).to receive(:load).and_call_original
    allow(GlobalConfigService).to receive(:load).with('PATHORS_OAUTH_CLIENT_ID', nil).and_return('pathors_client')
    allow(GlobalConfigService).to receive(:load).with('PATHORS_CONNECT_STATE_SECRET', nil).and_return(connect_secret)
    allow(GlobalConfigService).to receive(:load).with('PATHORS_API_URL', 'https://api.pathors.com').and_return('https://api.pathors.test')
  end

  describe 'GET /api/v1/pathors/connection' do
    it 'returns unauthorized for an unauthenticated user' do
      get '/api/v1/pathors/connection', as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'lists only the accounts the user administers, with their Pathors binding', :aggregate_failures do
      connected_account = create(:account, name: 'Beta Care')
      create(:account_user, account: connected_account, user: admin, role: :administrator)
      create(:agent_bot, account: connected_account, outgoing_url: bot_url)
      create(:integrations_hook, account: connected_account, app_id: 'pathors', settings: { organization_id: other_organization_id })
      agent_account = create(:account, name: 'Agent Only')
      create(:account_user, account: agent_account, user: admin, role: :agent)

      get '/api/v1/pathors/connection', headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['accounts']).to eq(
        [
          { 'id' => account.id, 'name' => 'Acme Support', 'connected' => false, 'organization_id' => nil },
          { 'id' => connected_account.id, 'name' => 'Beta Care', 'connected' => true, 'organization_id' => other_organization_id }
        ]
      )
    end

    it 'reports whether a new account can be created' do
      allow(GlobalConfigService).to receive(:load).with('CREATE_NEW_ACCOUNT_FROM_DASHBOARD', 'false').and_return('true')

      get '/api/v1/pathors/connection', headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body).to eq('can_create_account' => true, 'accounts' => [])
    end
  end

  describe 'POST /api/v1/pathors/connection' do
    let(:params) { { account_id: account.id, organization_id: organization_id } }

    it 'refuses an agent of the account' do
      post '/api/v1/pathors/connection', params: params, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'refuses an account the user does not belong to' do
      other_account = create(:account)

      post '/api/v1/pathors/connection', params: params.merge(account_id: other_account.id),
                                         headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'returns the Pathors authorize URL with the organization signed into the connect token', :aggregate_failures do
      post '/api/v1/pathors/connection', params: params, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      authorize_url = response.parsed_body['authorize_url']
      expect(authorize_url).to start_with('https://api.pathors.test/oauth/authorize?response_type=code')
      expect(authorize_url).to include('client_id=pathors_client', 'scope=chatwoot%3Aconnect')

      claims = decoded_connect_token(authorize_url)
      expect(claims).to include('account_id' => account.id, 'account_name' => 'Acme Support', 'organization_id' => organization_id)
      expect(claims['exp']).to be > Time.current.to_i
      query = CGI.parse(URI.parse(authorize_url).query)
      expect(query['state']).to eq(query['connect_token'])
    end

    it 'refuses an organization id that is not a UUID' do
      post '/api/v1/pathors/connection', params: params.merge(organization_id: 'org-1'),
                                         headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'refuses an account connected to another Pathors organization' do
      create(:agent_bot, account: account, outgoing_url: bot_url)
      create(:integrations_hook, account: account, app_id: 'pathors', settings: { organization_id: other_organization_id })

      post '/api/v1/pathors/connection', params: params, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'allows reconnecting an account to the same organization' do
      create(:agent_bot, account: account, outgoing_url: bot_url)
      create(:integrations_hook, account: account, app_id: 'pathors', settings: { organization_id: organization_id })

      post '/api/v1/pathors/connection', params: params, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
    end

    it 'allows retrying an unfinished connect to another organization' do
      create(:integrations_hook, account: account, app_id: 'pathors', settings: { organization_id: other_organization_id })

      post '/api/v1/pathors/connection', params: params, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
    end

    it 'refuses when the Pathors connection is not configured' do
      allow(GlobalConfigService).to receive(:load).with('PATHORS_CONNECT_STATE_SECRET', nil).and_return(nil)

      post '/api/v1/pathors/connection', params: params, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'POST /api/v1/pathors/connection/accounts' do
    let(:params) { { account_name: 'Gamma Desk', organization_id: organization_id } }
    # built up front: the agent's own account must not count as a created one
    let!(:auth_headers) { agent.create_new_auth_token }

    context 'when the installation allows creating accounts from the dashboard' do
      before do
        allow(GlobalConfigService).to receive(:load).with('CREATE_NEW_ACCOUNT_FROM_DASHBOARD', 'false').and_return('true')
      end

      it 'creates the account with the user as administrator and returns the authorize URL', :aggregate_failures do
        expect do
          post '/api/v1/pathors/connection/accounts', params: params, headers: auth_headers, as: :json
        end.to change(Account, :count).by(1)

        expect(response).to have_http_status(:ok)
        new_account = Account.find(response.parsed_body['account_id'])
        expect(new_account.name).to eq('Gamma Desk')
        expect(new_account.account_users.find_by(user: agent)).to be_administrator

        claims = decoded_connect_token(response.parsed_body['authorize_url'])
        expect(claims).to include('account_id' => new_account.id, 'organization_id' => organization_id)
      end

      it 'refuses a blank account name' do
        expect do
          post '/api/v1/pathors/connection/accounts', params: params.merge(account_name: '  '),
                                                      headers: auth_headers, as: :json
        end.not_to change(Account, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'refuses an organization id that is not a UUID without creating the account' do
        expect do
          post '/api/v1/pathors/connection/accounts', params: params.merge(organization_id: 'not-a-uuid'),
                                                      headers: auth_headers, as: :json
        end.not_to change(Account, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    it 'refuses when the installation does not allow creating accounts' do
      allow(GlobalConfigService).to receive(:load).with('CREATE_NEW_ACCOUNT_FROM_DASHBOARD', 'false').and_return('false')

      expect do
        post '/api/v1/pathors/connection/accounts', params: params, headers: auth_headers, as: :json
      end.not_to change(Account, :count)

      expect(response).to have_http_status(:forbidden)
    end
  end
end
