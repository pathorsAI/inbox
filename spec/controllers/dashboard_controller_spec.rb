require 'rails_helper'

describe '/app/login', type: :request do
  context 'without DEFAULT_LOCALE' do
    it 'renders the dashboard' do
      get '/app/login'
      expect(response).to have_http_status(:success)
    end
  end

  context 'with DEFAULT_LOCALE' do
    it 'renders the dashboard' do
      with_modified_env DEFAULT_LOCALE: 'pt_BR' do
        get '/app/login'
        expect(response).to have_http_status(:success)
        expect(response.body).to include "selectedLocale: 'pt_BR'"
      end
    end
  end

  context 'with Pathors login configured' do
    after { GlobalConfig.clear_cache }

    it 'offers only the Pathors login method' do
      GlobalConfig.clear_cache
      with_modified_env PATHORS_LOGIN_CLIENT_ID: 'inbox-login', PATHORS_LOGIN_CLIENT_SECRET: 'secret' do
        get '/app/login'
      end

      expect(response.body).to include('allowedLoginMethods: ["pathors"]')
      expect(response.body).to include("pathorsLoginEnabled: 'true'")
    end

    it 'keeps password login without the client secret' do
      GlobalConfig.clear_cache
      with_modified_env PATHORS_LOGIN_CLIENT_ID: 'inbox-login' do
        get '/app/login'
      end

      expect(response.body).to include('allowedLoginMethods: ["email"]')
      expect(response.body).to include("pathorsLoginEnabled: 'false'")
    end
  end

  context 'with non-HTML format' do
    it 'returns not acceptable for JSON with error message' do
      get '/app/login', headers: { 'Accept' => 'application/json' }
      expect(response).to have_http_status(:not_acceptable)
      expect(response.parsed_body).to eq({ 'error' => 'Please use API routes instead of dashboard routes for JSON requests' })
    end
  end

  # Routes are loaded once on app start
  # hence Rails.application.reload_routes! is used in this spec
  # ref : https://stackoverflow.com/a/63584877/939299
  context 'with CW_API_ONLY_SERVER true' do
    it 'returns 404' do
      with_modified_env CW_API_ONLY_SERVER: 'true' do
        Rails.application.reload_routes!
        get '/app/login'
        expect(response).to have_http_status(:not_found)
      end
      Rails.application.reload_routes!
    end
  end

  context 'when the host is a portal custom domain' do
    let(:account) { create(:account) }
    let(:portal) do
      create(:portal, account: account, custom_domain: 'support.example.test',
                      config: { 'layout' => 'focused', 'allowed_locales' => ['en'], 'default_locale' => 'en' })
    end

    it 'renders the help center home in the layout the portal selected' do
      host! portal.custom_domain
      get '/'
      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-layout="focused"')
      expect(response.body).not_to include('sdk.js')
    end
  end
end
