module Pathors::IntegrationHelper
  # Proof-of-initiation token for the Pathors OAuth connect flow.
  #
  # Signed with the shared connect secret (PATHORS_CONNECT_STATE_SECRET on both
  # deployments), it tells the Pathors authorization server which Chatwoot
  # account the connect is about — and that an administrator of that account,
  # not someone with a hand-crafted URL, initiated it. It doubles as the OAuth
  # `state` parameter so the callback can recover the account without session
  # storage.
  #
  # Modeled on Linear::IntegrationHelper, with two deliberate differences:
  # a dedicated shared secret (Pathors stores the OAuth client secret hashed,
  # so it cannot verify an HMAC), and an explicit 5-minute exp (the verifier
  # also enforces a max age on iat).
  #
  # `organization_id` is only present when the connect started on the Pathors
  # side (Api::V1::Pathors::ConnectionsController): the organization the user
  # came from, signed so Pathors can lock its consent page to it. It is a hint,
  # not a grant — Pathors still checks the user may bind that organization.
  TOKEN_TTL = 5.minutes

  def generate_pathors_token(account, organization_id: nil)
    return if pathors_connect_secret.blank?

    JWT.encode(pathors_token_payload(account, organization_id: organization_id), pathors_connect_secret, 'HS256')
  rescue StandardError => e
    Rails.logger.error("Failed to generate Pathors connect token: #{e.message}")
    nil
  end

  def pathors_token_payload(account, organization_id: nil)
    {
      account_id: account.id,
      account_name: account.name,
      organization_id: organization_id,
      iat: Time.current.to_i,
      exp: TOKEN_TTL.from_now.to_i
    }.compact
  end

  # The Pathors authorize request that starts the connect for `account`.
  # Nil when the OAuth client or the connect secret is not configured, since
  # such a request could only fail.
  def pathors_authorize_url(account, organization_id: nil)
    client_id = GlobalConfigService.load('PATHORS_OAUTH_CLIENT_ID', nil)
    connect_token = generate_pathors_token(account, organization_id: organization_id)
    return if client_id.blank? || connect_token.blank?

    api_url = GlobalConfigService.load('PATHORS_API_URL', 'https://api.pathors.com')
    [
      "#{api_url}/oauth/authorize?response_type=code",
      "client_id=#{client_id}",
      "redirect_uri=#{CGI.escape(Integrations::App.pathors_integration_url)}",
      'scope=chatwoot%3Aconnect',
      # The signed token proves which account this is about; it doubles as
      # `state` so the callback can recover the account statelessly.
      "connect_token=#{connect_token}",
      "state=#{connect_token}"
    ].join('&')
  end

  # @return [Integer, nil] the account ID or nil if the token is invalid
  def verify_pathors_token(token)
    return if token.blank? || pathors_connect_secret.blank?

    JWT.decode(token, pathors_connect_secret, true, {
                 algorithm: 'HS256',
                 verify_expiration: true
               }).first['account_id']
  rescue StandardError => e
    Rails.logger.error("Unexpected error verifying Pathors connect token: #{e.message}")
    nil
  end

  private

  def pathors_connect_secret
    @pathors_connect_secret ||= GlobalConfigService.load('PATHORS_CONNECT_STATE_SECRET', nil)
  end
end
