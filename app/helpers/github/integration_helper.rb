# Signs the account id into the `state` of the GitHub App install URL. GitHub
# hands `state` back on the callback, and it is the only thing that tells us
# which account started the install.
module Github::IntegrationHelper
  # The state only names the account; binding is gated separately by the
  # admin session, so a long TTL costs nothing and survives slow installs.
  STATE_TTL = 1.hour

  def generate_github_state(account_id)
    secret = github_client_secret
    return if secret.blank?

    now = Time.current
    JWT.encode({ sub: account_id, iat: now.to_i, exp: (now + STATE_TTL).to_i }, secret, 'HS256')
  end

  def verify_github_state(token)
    decode_github_state(token, verify_expiration: true)
  end

  # Signed by us but past its expiry: good enough to send the admin back to
  # their own settings page to retry, never to bind anything.
  def expired_github_state_account_id(token)
    decode_github_state(token, verify_expiration: false)
  end

  private

  def decode_github_state(token, verify_expiration:)
    secret = github_client_secret
    return if token.blank? || secret.blank?

    JWT.decode(token, secret, true, { algorithm: 'HS256', required_claims: %w[exp], verify_expiration: verify_expiration }).first['sub']
  rescue JWT::DecodeError => e
    Rails.logger.warn("Rejected GitHub install state: #{e.message}")
    nil
  end

  def github_client_secret
    GlobalConfigService.load('GITHUB_APP_CLIENT_SECRET', nil)
  end
end
