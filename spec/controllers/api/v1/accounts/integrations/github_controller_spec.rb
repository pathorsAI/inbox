require 'rails_helper'

RSpec.describe 'GitHub Integration API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:hook) { create(:integrations_hook, :github, account: account, settings: {}) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/integrations/github" }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }
  let(:repositories_url) { 'https://api.github.com/installation/repositories?per_page=100' }

  before do
    allow(GlobalConfigService).to receive(:load).and_call_original
    allow(GlobalConfigService).to receive(:load).with('GITHUB_APP_ID', nil).and_return('123456')
    allow(GlobalConfigService).to receive(:load).with('GITHUB_APP_PRIVATE_KEY', nil).and_return(OpenSSL::PKey::RSA.generate(2048).to_pem)
    stub_request(:post, 'https://api.github.com/app/installations/4242/access_tokens')
      .to_return(status: 201, body: { token: 'ghs_token', expires_at: 1.hour.from_now.iso8601 }.to_json, headers: json_headers)
    stub_request(:get, repositories_url)
      .to_return(status: 200, body: { repositories: [{ full_name: 'pathorsAI/pathors' }, { full_name: 'pathorsAI/inbox' }] }.to_json,
                 headers: json_headers)
  end

  describe 'POST /api/v1/accounts/:account_id/integrations/github' do
    let(:client_secret) { 'github-client-secret' }
    let(:state) { JWT.encode({ sub: account.id, iat: Time.current.to_i, exp: 10.minutes.from_now.to_i }, client_secret, 'HS256') }
    let(:visible_installations) { [{ id: 4242 }] }
    let(:connect_params) { { code: 'oauth-code', installation_id: '4242', state: state } }

    before do
      hook.destroy!
      allow(GlobalConfigService).to receive(:load).with('GITHUB_APP_CLIENT_ID', nil).and_return('Iv1.client')
      allow(GlobalConfigService).to receive(:load).with('GITHUB_APP_CLIENT_SECRET', nil).and_return(client_secret)
      stub_request(:post, 'https://github.com/login/oauth/access_token')
        .to_return(status: 200, body: { access_token: 'ghu_user_token' }.to_json, headers: json_headers)
      stub_request(:get, 'https://api.github.com/user/installations?per_page=100')
        .with(headers: { 'Authorization' => 'Bearer ghu_user_token' })
        .to_return(status: 200, body: { installations: visible_installations }.to_json, headers: json_headers)
    end

    it 'binds an installation the authorizing user can see' do
      post base_url, params: connect_params, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      connected = account.hooks.find_by!(app_id: 'github')
      expect(connected.reference_id).to eq('4242')
      expect(connected.settings).to eq({})
      expect(response.parsed_body['reference_id']).to eq('4242')
    end

    it 'refuses a forged installation id and writes nothing' do
      post base_url, params: connect_params.merge(installation_id: '9999'), headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['reason']).to eq('installation_not_verified')
      expect(account.hooks.where(app_id: 'github')).to be_empty
    end

    it 'refuses a state minted for another account' do
      other_state = JWT.encode({ sub: create(:account).id, exp: 10.minutes.from_now.to_i }, client_secret, 'HS256')

      post base_url, params: connect_params.merge(state: other_state), headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['reason']).to eq('connection_failed')
      expect(account.hooks.where(app_id: 'github')).to be_empty
      expect(WebMock).not_to have_requested(:post, 'https://github.com/login/oauth/access_token')
    end

    it 'keeps the label and a repository the installation still grants when reconnecting' do
      previous = create(:integrations_hook, :github, account: account, reference_id: '1',
                                                     settings: { 'repository' => 'pathorsai/inbox', 'label' => 'support' })
      previous.prompt_reauthorization!

      post base_url, params: connect_params, headers: admin.create_new_auth_token, as: :json

      previous.reload
      expect(previous.reference_id).to eq('4242')
      expect(previous.settings).to eq('repository' => 'pathorsai/inbox', 'label' => 'support')
      expect(previous.reauthorization_required?).to be(false)
    end

    it 'drops a repository the new installation does not grant' do
      create(:integrations_hook, :github, account: account, reference_id: '1', settings: { 'repository' => 'someone/else', 'label' => 'support' })

      post base_url, params: connect_params, headers: admin.create_new_auth_token, as: :json

      expect(account.hooks.find_by!(app_id: 'github').settings).to eq('label' => 'support')
    end

    it 'reports a code GitHub rejects' do
      stub_request(:post, 'https://github.com/login/oauth/access_token')
        .to_return(status: 200, body: { error: 'bad_verification_code' }.to_json, headers: json_headers)

      post base_url, params: connect_params, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['reason']).to eq('connection_failed')
    end

    it 'is limited to administrators' do
      post base_url, params: connect_params, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(account.hooks.where(app_id: 'github')).to be_empty
    end
  end

  describe 'GET /api/v1/accounts/:account_id/integrations/github/repositories' do
    it 'lists the repositories the installation grants' do
      get "#{base_url}/repositories", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(%w[pathorsAI/pathors pathorsAI/inbox])
    end

    it 'is limited to administrators' do
      get "#{base_url}/repositories", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'asks for a reconnect when GitHub no longer accepts the installation' do
      stub_request(:post, 'https://api.github.com/app/installations/4242/access_tokens').to_return(status: 404, body: '{}', headers: json_headers)

      get "#{base_url}/repositories", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(hook.reauthorization_required?).to be(true)
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/integrations/github' do
    it 'saves a granted repository and the label' do
      patch base_url, params: { repository: 'pathorsai/inbox', label: 'support' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(hook.reload.settings).to eq('repository' => 'pathorsAI/inbox', 'label' => 'support')
      expect(response.parsed_body['settings']).to eq('repository' => 'pathorsAI/inbox', 'label' => 'support')
    end

    it 'refuses a repository outside the installation' do
      patch base_url, params: { repository: 'someone/else' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(hook.reload.settings).to eq({})
    end

    it 'is limited to administrators' do
      patch base_url, params: { repository: 'pathorsAI/inbox' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(hook.reload.settings).to eq({})
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/integrations/github' do
    it 'removes the hook without calling GitHub' do
      delete base_url, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(account.hooks.where(app_id: 'github')).to be_empty
      expect(WebMock).not_to have_requested(:any, /github\.com/)
    end
  end
end
