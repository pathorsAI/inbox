require 'rails_helper'

RSpec.describe 'Sign in with Pathors', type: :request do
  let(:pathors_env) do
    { PATHORS_LOGIN_CLIENT_ID: 'inbox-login', PATHORS_LOGIN_CLIENT_SECRET: 'secret', FRONTEND_URL: 'http://localhost:3000' }
  end
  let(:pathors_auth) do
    {
      provider: 'pathors',
      uid: 'pathors-sub-1',
      info: { email: 'agent@example.com', name: 'Agent Smith', image: nil, email_verified: true }
    }
  end

  before do
    # OmniAuth redirects to its full_host (FRONTEND_URL at boot); stay on it so the session cookie follows.
    host! 'localhost:3000'
    GlobalConfig.clear_cache
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:pathors] = OmniAuth::AuthHash.new(pathors_auth)
  end

  after do
    OmniAuth.config.mock_auth.delete(:pathors)
    GlobalConfig.clear_cache
  end

  def complete_pathors_login(query = '')
    post "/omniauth/pathors#{query}"
    follow_redirect!
    expect(URI.parse(response.location).path).to eq('/auth/pathors/callback')
    follow_redirect!
  end

  def login_redirect_params
    Rack::Utils.parse_query(URI.parse(response.location).query)
  end

  it 'links an existing user by email and signs them in with an sso token' do
    user = create(:user, email: 'agent@example.com')

    with_modified_env(pathors_env) { complete_pathors_login }

    expect(user.reload.pathors_uid).to eq('pathors-sub-1')
    expect(response.location).to start_with('http://localhost:3000/app/login?')
    expect(login_redirect_params['email']).to eq('agent%40example.com')
    expect(user.valid_sso_auth_token?(login_redirect_params['sso_auth_token'])).to be(true)
  end

  it 'finds a user by pathors_uid even when the email differs' do
    user = create(:user, email: 'renamed@example.com', pathors_uid: 'pathors-sub-1')

    with_modified_env(pathors_env) { complete_pathors_login }

    expect(login_redirect_params['email']).to eq('renamed%40example.com')
    expect(user.valid_sso_auth_token?(login_redirect_params['sso_auth_token'])).to be(true)
  end

  it 'creates a confirmed user without any account when none exists' do
    with_modified_env(pathors_env) { complete_pathors_login }

    user = User.find_by!(email: 'agent@example.com')
    expect(user).to have_attributes(name: 'Agent Smith', pathors_uid: 'pathors-sub-1', type: nil)
    expect(user.confirmed?).to be(true)
    expect(user.accounts).to be_empty
    expect(user.valid_sso_auth_token?(login_redirect_params['sso_auth_token'])).to be(true)
  end

  it 'confirms an invited user who has not set a password yet' do
    invited = create(:user, email: 'agent@example.com', skip_confirmation: false)
    expect(invited.confirmed?).to be(false)

    with_modified_env(pathors_env) { complete_pathors_login }

    expect(invited.reload).to have_attributes(pathors_uid: 'pathors-sub-1')
    expect(invited.confirmed?).to be(true)
  end

  it 'refuses an unverified Pathors email' do
    OmniAuth.config.mock_auth[:pathors] = OmniAuth::AuthHash.new(pathors_auth.deep_merge(info: { email_verified: false }))
    create(:user, email: 'agent@example.com')

    with_modified_env(pathors_env) { complete_pathors_login }

    expect(response).to redirect_to('http://localhost:3000/app/login?error=pathors-email-unverified')
    expect(User.from_email('agent@example.com').pathors_uid).to be_nil
  end

  it 'refuses an email already linked to another Pathors account' do
    create(:user, email: 'agent@example.com', pathors_uid: 'pathors-sub-other')

    with_modified_env(pathors_env) { complete_pathors_login }

    expect(response).to redirect_to('http://localhost:3000/app/login?error=pathors-account-mismatch')
  end

  it 'carries valid deep-link params through the round trip and drops malformed ones' do
    create(:user, email: 'agent@example.com')

    with_modified_env(pathors_env) do
      complete_pathors_login('?sso_account_id=12&sso_conversation_id=abc&sso_route_path=contacts/7&redirect_url=https://evil.example')
    end

    expect(login_redirect_params.slice('sso_account_id', 'sso_conversation_id', 'sso_route_path', 'redirect_url'))
      .to eq('sso_account_id' => '12', 'sso_route_path' => 'contacts/7')
  end

  it 'sends an OmniAuth failure back to the login page' do
    OmniAuth.config.mock_auth[:pathors] = :invalid_credentials

    with_modified_env(pathors_env) do
      post '/omniauth/pathors'
      follow_redirect!
      follow_redirect! while response.redirect? && response.location.exclude?('/app/login')
    end

    expect(response).to redirect_to('http://localhost:3000/app/login?error=pathors-login-failed')
  end

  context 'with the real strategy against a stubbed Pathors server' do
    before { OmniAuth.config.test_mode = false }
    after { OmniAuth.config.test_mode = true }

    it 'runs authorize with PKCE and state, then reads the identity from userinfo' do
      stub_request(:post, 'https://api.pathors.com/oauth/token')
        .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                   body: { access_token: 'pathors-access', token_type: 'Bearer', refresh_token: 'r' }.to_json)
      identity = { sub: 'pathors-sub-9', email: 'new@example.com', name: 'New Agent', email_verified: true }
      stub_request(:get, 'https://api.pathors.com/oauth/userinfo')
        .with(headers: { 'Authorization' => 'Bearer pathors-access' })
        .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: identity.to_json)

      with_modified_env(pathors_env) do
        post '/omniauth/pathors?sso_route_path=contacts'
        authorize = URI.parse(response.location)
        query = Rack::Utils.parse_query(authorize.query)
        expect("#{authorize.host}#{authorize.path}").to eq('api.pathors.com/oauth/authorize')
        expect(query).to include('client_id' => 'inbox-login', 'response_type' => 'code', 'scope' => 'openid email profile',
                                 'redirect_uri' => 'http://localhost:3000/omniauth/pathors/callback', 'code_challenge_method' => 'S256')

        get '/omniauth/pathors/callback', params: { code: 'pathors-code', state: query['state'] }
        follow_redirect!
      end

      expect(a_request(:post, 'https://api.pathors.com/oauth/token')
        .with(body: hash_including('code' => 'pathors-code', 'redirect_uri' => 'http://localhost:3000/omniauth/pathors/callback',
                                   'code_verifier' => /\A\h{128}\z/))).to have_been_made
      expect(User.from_email('new@example.com')).to have_attributes(pathors_uid: 'pathors-sub-9', name: 'New Agent')
      expect(login_redirect_params['sso_route_path']).to eq('contacts')
    end

    it 'refuses a callback whose state does not match' do
      with_modified_env(pathors_env) do
        post '/omniauth/pathors'
        get '/omniauth/pathors/callback', params: { code: 'pathors-code', state: 'forged' }
        follow_redirect! while response.redirect? && response.location.exclude?('/app/login')
      end

      expect(response).to redirect_to('http://localhost:3000/app/login?error=pathors-login-failed')
    end
  end

  it 'is not routable while the switch is off' do
    with_modified_env(FRONTEND_URL: 'http://localhost:3000') do
      post '/omniauth/pathors'
      expect(response).to have_http_status(:not_found)

      get '/omniauth/pathors/callback'
      expect(response).to have_http_status(:not_found)
    end
  end
end
