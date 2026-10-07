# Super admin sign-in through Cloudflare Access for SaaS (OIDC). With the three
# CF_ACCESS_OIDC_* values set, this replaces the password form; only an existing
# SuperAdmin with the verified email gets in, nobody is created here. The values
# are read from ENV first because a super admin cannot fix their own login from
# inside the panel.
class SuperAdmin::SsoController < ApplicationController
  CONFIG_KEYS = %w[CF_ACCESS_OIDC_ISSUER CF_ACCESS_OIDC_CLIENT_ID CF_ACCESS_OIDC_CLIENT_SECRET].freeze
  SESSION_KEY = :super_admin_sso

  before_action :ensure_enabled

  def self.sso_config
    CONFIG_KEYS.index_with { |key| ENV[key].presence || GlobalConfig.get_value(key).presence }
  end

  def self.enabled?
    sso_config.values.all?(&:present?)
  end

  def new
    state = SecureRandom.hex(24)
    verifier = SecureRandom.urlsafe_base64(64)
    session[SESSION_KEY] = { 'state' => state, 'verifier' => verifier }

    redirect_to client.auth_code.authorize_url(
      redirect_uri: callback_url,
      scope: 'openid email profile',
      state: state,
      code_challenge: Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false),
      code_challenge_method: 'S256'
    ), allow_other_host: true
  end

  def callback
    stash = session.delete(SESSION_KEY) || {}
    return deny unless stash['state'].present? && ActiveSupport::SecurityUtils.secure_compare(stash['state'], params[:state].to_s)

    super_admin = super_admin_for(identity(stash['verifier']))
    return deny if super_admin.nil?

    sign_in(:super_admin, super_admin)
    redirect_to super_admin_root_path
  rescue OAuth2::Error, Faraday::Error => e
    Rails.logger.warn("Super admin SSO failed: #{e.message}")
    deny
  end

  private

  def ensure_enabled
    raise ActionController::RoutingError, 'Not Found' unless self.class.enabled?
  end

  def identity(verifier)
    token = client.auth_code.get_token(params[:code].to_s, redirect_uri: callback_url, code_verifier: verifier)
    token.get("#{issuer}/userinfo").parsed
  end

  def super_admin_for(info)
    # Cloudflare Access's policy is the gate; refuse only an explicit "not verified".
    return if info['email_verified'] == false

    SuperAdmin.from_email(info['email'].to_s)
  end

  def deny
    redirect_to new_super_admin_session_path, flash: { error: 'Single sign-on failed. Use an account that is a super admin here.' }
  end

  def client
    config = self.class.sso_config
    OAuth2::Client.new(
      config['CF_ACCESS_OIDC_CLIENT_ID'],
      config['CF_ACCESS_OIDC_CLIENT_SECRET'],
      site: issuer, authorize_url: "#{issuer}/authorization", token_url: "#{issuer}/token"
    )
  end

  def issuer
    self.class.sso_config['CF_ACCESS_OIDC_ISSUER'].delete_suffix('/')
  end

  def callback_url
    "#{ENV.fetch('FRONTEND_URL', '')}/super_admin/sso/callback"
  end
end
