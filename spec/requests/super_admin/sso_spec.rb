require 'rails_helper'

RSpec.describe 'Super admin single sign-on', type: :request do
  let(:issuer) { 'https://team.cloudflareaccess.com/cdn-cgi/access/sso/oidc/cf-client' }
  let(:cf_env) do
    {
      CF_ACCESS_OIDC_ISSUER: issuer, CF_ACCESS_OIDC_CLIENT_ID: 'cf-client', CF_ACCESS_OIDC_CLIENT_SECRET: 'cf-secret',
      FRONTEND_URL: 'http://www.example.com'
    }
  end
  let!(:super_admin) { create(:super_admin, email: 'ops@pathors.com') }
  let(:userinfo) { { email: 'Ops@pathors.com', email_verified: true } }

  around do |example|
    with_modified_env(cf_env) { example.run }
  end

  before do
    stub_request(:post, "#{issuer}/token").to_return(
      status: 200, headers: { 'Content-Type' => 'application/json' }, body: { access_token: 'cf-access', token_type: 'Bearer' }.to_json
    )
    stub_request(:get, "#{issuer}/userinfo").with(headers: { 'Authorization' => 'Bearer cf-access' })
                                            .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: userinfo.to_json)
  end

  def start_sso
    get '/super_admin/sso'
    authorize = URI.parse(response.location)
    query = Rack::Utils.parse_query(authorize.query)
    expect("#{authorize.scheme}://#{authorize.host}#{authorize.path}").to eq("#{issuer}/authorization")
    expect(query).to include('client_id' => 'cf-client', 'redirect_uri' => 'http://www.example.com/super_admin/sso/callback',
                             'code_challenge_method' => 'S256')
    query['state']
  end

  it 'signs in an existing super admin with a verified email' do
    state = start_sso
    get '/super_admin/sso/callback', params: { code: 'cf-code', state: state }

    expect(response).to redirect_to(super_admin_root_path)
    expect(a_request(:post, "#{issuer}/token").with(body: hash_including('code' => 'cf-code', 'code_verifier' => /\A[\w-]{40,}\z/)))
      .to have_been_made
    get super_admin_root_path
    expect(response).to have_http_status(:success)
  end

  it 'refuses a mismatched state' do
    start_sso
    get '/super_admin/sso/callback', params: { code: 'cf-code', state: 'forged' }

    expect(response).to redirect_to(new_super_admin_session_path)
    expect(a_request(:post, "#{issuer}/token")).not_to have_been_made
  end

  context 'when the email is not a super admin' do
    let(:userinfo) { { email: 'someone@pathors.com', email_verified: true } }

    it 'refuses and creates nobody' do
      state = start_sso
      get '/super_admin/sso/callback', params: { code: 'cf-code', state: state }

      expect(response).to redirect_to(new_super_admin_session_path)
      expect(User.from_email('someone@pathors.com')).to be_nil
    end
  end

  context 'when the email is not verified' do
    let(:userinfo) { { email: 'ops@pathors.com', email_verified: false } }

    it 'refuses' do
      state = start_sso
      get '/super_admin/sso/callback', params: { code: 'cf-code', state: state }

      expect(response).to redirect_to(new_super_admin_session_path)
    end
  end

  it 'refuses the password form and offers only single sign-on' do
    post '/super_admin/sign_in', params: { super_admin: { email: super_admin.email, password: super_admin.password } }
    expect(response).to redirect_to(super_admin_session_path)

    get super_admin_root_path
    expect(response).to redirect_to(new_super_admin_session_path)

    get new_super_admin_session_path
    expect(response.body).to include('Sign in with single sign-on')
    expect(response.body).not_to include('name="super_admin[password]"')
  end

  context 'without Cloudflare Access configured' do
    let(:cf_env) { { CF_ACCESS_OIDC_ISSUER: nil, CF_ACCESS_OIDC_CLIENT_ID: nil, CF_ACCESS_OIDC_CLIENT_SECRET: nil } }

    it 'keeps the password form and hides single sign-on' do
      get '/super_admin/sso'
      expect(response).to have_http_status(:not_found)

      post '/super_admin/sign_in', params: { super_admin: { email: super_admin.email, password: super_admin.password } }
      expect(response).to redirect_to(super_admin_root_path)
    end
  end
end
