require 'rails_helper'

RSpec.describe 'Super Admin settings', type: :request do
  let!(:super_admin) { create(:super_admin) }

  describe 'GET /super_admin/settings' do
    before { sign_in(super_admin, scope: :super_admin) }

    it 'lists the features this installation ships' do
      get '/super_admin/settings'

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Voice Calls', 'Help Center')
    end

    it 'does not advertise the enterprise edition' do
      get '/super_admin/settings'

      expect(response.body).not_to include('>EE<')
      expect(response.body).not_to include('Switch to Enterprise edition')
      expect(response.body).not_to include('SAML SSO')
      expect(response.body).not_to include('Custom Branding')
      expect(response.body).not_to include('Disable Branding')
    end

    it 'does not list Captain' do
      get '/super_admin/settings'

      expect(response.body).not_to include('Enable AI-powered conversations with your customers.')
    end
  end
end
