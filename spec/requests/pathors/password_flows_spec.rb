require 'rails_helper'

RSpec.describe 'Password flows under Pathors login', type: :request do
  let(:pathors_env) { { PATHORS_LOGIN_CLIENT_ID: 'inbox-login', PATHORS_LOGIN_CLIENT_SECRET: 'secret', ENABLE_ACCOUNT_SIGNUP: 'true' } }
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, email: 'agent@example.com', password: 'Password1!') }
  let(:refusal) { { 'error_code' => 'pathors_login_only' } }

  around do |example|
    GlobalConfig.clear_cache
    with_modified_env(pathors_env) { example.run }
    GlobalConfig.clear_cache
  end

  it 'refuses a password sign in' do
    post user_session_path, params: { email: user.email, password: 'Password1!' }, as: :json

    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body).to include(refusal)
  end

  it 'still signs in with a one-time sso_auth_token' do
    post user_session_path, params: { email: user.email, sso_auth_token: user.generate_sso_auth_token }, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('data', 'email')).to eq('agent@example.com')
  end

  it 'answers a stale sso_auth_token with bad credentials, not the Pathors-only refusal' do
    token = user.generate_sso_auth_token
    user.invalidate_sso_auth_token(token)

    post user_session_path, params: { email: user.email, sso_auth_token: token }, as: :json
    expect(response).to have_http_status(:unauthorized)

    post user_session_path, params: { email: user.email, sso_auth_token: 'unknown', password: 'Password1!' }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(response.headers['access-token']).to be_nil
  end

  it 'refuses password reset requests and resets' do
    post user_password_path, params: { email: user.email }, as: :json
    expect(response).to have_http_status(:forbidden)

    token = user.send(:set_reset_password_token)
    put user_password_path, params: { reset_password_token: token, password: 'Newpass1!', password_confirmation: 'Newpass1!' }, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(user.reload.valid_password?('Password1!')).to be(true)
  end

  it 'refuses devise_token_auth registrations' do
    post user_registration_path, params: { email: 'new@example.com', password: 'Password1!', password_confirmation: 'Password1!' }, as: :json

    expect(response).to have_http_status(:forbidden)
    expect(User.from_email('new@example.com')).to be_nil
  end

  it 'refuses a profile password change and an email change, but saves other profile fields' do
    password_change = { current_password: 'Password1!', password: 'Newpass1!', password_confirmation: 'Newpass1!' }
    put '/api/v1/profile', headers: user.create_new_auth_token, params: { profile: password_change }, as: :json
    expect(response).to have_http_status(:forbidden)

    put '/api/v1/profile', headers: user.create_new_auth_token, params: { profile: { email: 'other@example.com' } }, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body['error']).to eq('Your email address comes from your Pathors account. Change it in Pathors.')

    put '/api/v1/profile', headers: user.create_new_auth_token, params: { profile: { name: 'Renamed', email: 'AGENT@example.com' } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(user.reload).to have_attributes(name: 'Renamed', email: 'agent@example.com')
  end

  it 'refuses Chatwoot MFA enrolment' do
    post '/api/v1/profile/mfa', headers: user.create_new_auth_token, as: :json

    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body).to include(refusal)
    expect(user.reload.otp_secret).to be_nil
  end

  it 'refuses the unauthenticated signup APIs' do
    post api_v1_accounts_url, params: { account_name: 'Acme', email: 'new@example.com', user_full_name: 'New', password: 'Password1!' }, as: :json
    expect(response).to have_http_status(:forbidden)

    post '/api/v2/accounts', params: { email: 'new@example.com', password: 'Password1!' }, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body).to include(refusal)
    expect(User.from_email('new@example.com')).to be_nil
  end

  it 'lets a signed-in user create their account' do
    pathors_user = create(:user, pathors_uid: 'pathors-sub-1')

    post api_v1_accounts_url, headers: pathors_user.create_new_auth_token, params: { account_name: 'Acme Support' }, as: :json

    expect(response).to have_http_status(:ok)
    expect(pathors_user.reload.accounts.pluck(:name)).to eq(['Acme Support'])
    expect(pathors_user.account_users.first.role).to eq('administrator')
  end

  context 'with the switch off' do
    let(:pathors_env) { { PATHORS_LOGIN_CLIENT_ID: nil, PATHORS_LOGIN_CLIENT_SECRET: nil } }

    it 'keeps password sign in' do
      post user_session_path, params: { email: user.email, password: 'Password1!' }, as: :json

      expect(response).to have_http_status(:ok)
    end
  end
end
