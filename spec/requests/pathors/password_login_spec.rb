require 'rails_helper'

# Sign in with Pathors is one more login option: with the client configured,
# every password flow works as in stock Chatwoot.
RSpec.describe 'Password login with Pathors login configured', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, email: 'agent@example.com', password: 'Password1!', pathors_uid: 'pathors-sub-1') }

  around do |example|
    GlobalConfig.clear_cache
    with_modified_env(PATHORS_LOGIN_CLIENT_ID: 'inbox-login', PATHORS_LOGIN_CLIENT_SECRET: 'secret') { example.run }
    GlobalConfig.clear_cache
  end

  it 'signs a Pathors-linked user in with their password' do
    post user_session_path, params: { email: user.email, password: 'Password1!' }, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('data', 'email')).to eq('agent@example.com')
  end

  it 'still signs in with a one-time sso_auth_token' do
    post user_session_path, params: { email: user.email, sso_auth_token: user.generate_sso_auth_token }, as: :json

    expect(response).to have_http_status(:ok)
  end

  it 'accepts a password reset request' do
    post user_password_path, params: { email: user.email }, as: :json

    expect(response).to have_http_status(:ok)
  end

  it 'lets the user change their password from the profile' do
    password_change = { current_password: 'Password1!', password: 'Newpass1!', password_confirmation: 'Newpass1!' }
    put '/api/v1/profile', headers: user.create_new_auth_token, params: { profile: password_change }, as: :json

    expect(response).to have_http_status(:ok)
    expect(user.reload.valid_password?('Newpass1!')).to be(true)
  end
end
