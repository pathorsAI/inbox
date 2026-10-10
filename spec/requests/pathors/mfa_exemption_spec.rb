require 'rails_helper'

RSpec.describe 'Account-enforced MFA for Pathors users', type: :request do
  let(:account) { create(:account) }
  let(:pathors_env) { { PATHORS_LOGIN_CLIENT_ID: 'inbox-login', PATHORS_LOGIN_CLIENT_SECRET: 'secret' } }

  before do
    skip('Skipping since MFA is not configured in this environment') unless Chatwoot.encryption_configured?
    account.update!(enforce_mfa: true)
  end

  around do |example|
    GlobalConfig.clear_cache
    example.run
    GlobalConfig.clear_cache
  end

  def list_conversations(user)
    get "/api/v1/accounts/#{account.id}/conversations", headers: { api_access_token: user.access_token.token }, as: :json
  end

  def expect_mfa_enrollment_required(user)
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body['error_code']).to eq('mfa_enrollment_required')
    expect(user.mfa_enforcement_pending?).to be(true)
  end

  context 'with Pathors login on' do
    around { |example| with_modified_env(pathors_env) { example.run } }

    it 'lets a user who signs in with Pathors use an API token' do
      user = create(:user, account: account, role: :agent, pathors_uid: 'pathors-sub-1')

      list_conversations(user)

      expect(response).to have_http_status(:success)
      expect(user.mfa_enforcement_pending?).to be(false)
    end

    it 'lets a Pathors system user use an API token' do
      user = create(:user, account: account, role: :administrator, email: "system+acct#{account.id}@inbox.pathors.com")

      list_conversations(user)

      expect(response).to have_http_status(:success)
      expect(user.mfa_enforcement_pending?).to be(false)
    end
  end

  context 'with Pathors login off' do
    it 'enforces MFA on a user linked to Pathors, who signs in with a password again' do
      user = create(:user, account: account, role: :agent, pathors_uid: 'pathors-sub-1')

      list_conversations(user)

      expect_mfa_enrollment_required(user)
    end

    it 'still lets a Pathors system user use an API token' do
      user = create(:user, account: account, role: :administrator, email: "system+acct#{account.id}@inbox.pathors.com")

      list_conversations(user)

      expect(response).to have_http_status(:success)
      expect(user.mfa_enforcement_pending?).to be(false)
    end
  end

  it 'still blocks other users who have not enrolled' do
    user = create(:user, account: account, role: :agent, email: 'system+acct1@inbox.pathors.com.evil.example')

    list_conversations(user)

    expect_mfa_enrollment_required(user)
  end
end
