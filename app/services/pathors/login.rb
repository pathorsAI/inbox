# Sign in with Pathors (pathorsAI/pathors#3316) is offered when both
# PATHORS_LOGIN_CLIENT_ID and PATHORS_LOGIN_CLIENT_SECRET are configured. It is
# one more login provider next to password and Google; nothing else changes.
# This is a separate OAuth client from the integration's PATHORS_OAUTH_CLIENT_ID.
module Pathors::Login
  # Pathors' per-account admin users, which call the API with an access token
  # and cannot enrol a TOTP. Must match the address Pathors generates in
  # packages/shared/src/integrations/chatwoot-admin-credentials.ts (pathorsAI/pathors).
  # This is a security boundary (it exempts the user from enforced MFA) that relies on
  # Pathors alone controlling the inbox.pathors.com mailbox domain; Pathors login also
  # refuses to link or create users with these addresses.
  SYSTEM_USER_EMAIL = /\Asystem\+acct\d+@inbox\.pathors\.com\z/i

  module_function

  def enabled?
    client_id.present? && client_secret.present?
  end

  def client_id
    GlobalConfigService.load('PATHORS_LOGIN_CLIENT_ID', nil)
  end

  def client_secret
    GlobalConfigService.load('PATHORS_LOGIN_CLIENT_SECRET', nil)
  end

  def api_url
    GlobalConfigService.load('PATHORS_API_URL', 'https://api.pathors.com')
  end

  def system_user?(user)
    SYSTEM_USER_EMAIL.match?(user.email.to_s)
  end
end
