# Signs the account id into the `state` of the GitHub App install URL. GitHub
# hands `state` back on the callback, and it is the only thing that tells us
# which account started the install.
module Github::IntegrationHelper
  STATE_TTL = 15.minutes

  def generate_github_state(account_id)
    secret = github_client_secret
    return if secret.blank?

    now = Time.current
    JWT.encode({ sub: account_id, iat: now.to_i, exp: (now + STATE_TTL).to_i }, secret, 'HS256')
  end

  def verify_github_state(token)
    secret = github_client_secret
    return if token.blank? || secret.blank?

    JWT.decode(token, secret, true, { algorithm: 'HS256', required_claims: %w[exp] }).first['sub']
  rescue JWT::DecodeError => e
    Rails.logger.warn("Rejected GitHub install state: #{e.message}")
    nil
  end

  private

  def github_client_secret
    GlobalConfigService.load('GITHUB_APP_CLIENT_SECRET', nil)
  end
end
