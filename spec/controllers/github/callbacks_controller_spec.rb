require 'rails_helper'

RSpec.describe Github::CallbacksController, type: :request do
  let(:account) { create(:account) }
  let(:client_secret) { 'github-client-secret' }
  let(:state) { JWT.encode({ sub: account.id, iat: Time.current.to_i, exp: 10.minutes.from_now.to_i }, client_secret, 'HS256') }
  let(:settings_url) { "http://www.example.com/app/accounts/#{account.id}/settings/integrations/github" }

  around do |example|
    with_modified_env(FRONTEND_URL: 'http://www.example.com') { example.run }
  end

  before do
    allow(GlobalConfigService).to receive(:load).and_call_original
    allow(GlobalConfigService).to receive(:load).with('GITHUB_APP_CLIENT_SECRET', nil).and_return(client_secret)
  end

  describe 'GET /github/callback' do
    it 'hands the install to the settings page of the account named in the state, without binding it' do
      get github_callback_path, params: { code: 'oauth-code', installation_id: '4242', setup_action: 'install', state: state }

      expect(response).to redirect_to("#{settings_url}?#{{ code: 'oauth-code', installation_id: '4242', state: state }.to_query}")
      expect(Integrations::Hook.where(app_id: 'github')).to be_empty
      expect(WebMock).not_to have_requested(:any, /github\.com/)
    end

    it 'sends a pending org approval back to the settings page' do
      get github_callback_path, params: { setup_action: 'request', state: state }

      expect(response).to redirect_to("#{settings_url}?setup_action=request")
    end

    it 'redirects to the app root without naming any account when the state is forged' do
      forged = JWT.encode({ sub: account.id, exp: 10.minutes.from_now.to_i }, 'not-the-secret', 'HS256')

      get github_callback_path, params: { code: 'oauth-code', installation_id: '4242', state: forged }

      expect(response).to redirect_to('http://www.example.com')
    end

    it 'rejects an expired state' do
      expired = JWT.encode({ sub: account.id, exp: 1.minute.ago.to_i }, client_secret, 'HS256')

      get github_callback_path, params: { code: 'oauth-code', installation_id: '4242', state: expired }

      expect(response).to redirect_to('http://www.example.com')
    end

    it 'rejects a state without an expiry' do
      eternal = JWT.encode({ sub: account.id }, client_secret, 'HS256')

      get github_callback_path, params: { code: 'oauth-code', installation_id: '4242', state: eternal }

      expect(response).to redirect_to('http://www.example.com')
    end
  end
end
