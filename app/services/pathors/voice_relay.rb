# Shared plumbing for dashboard actions that are relayed to the Pathors backend's
# `voice/*` endpoints (join, hangup). The backend owns the LiveKit room the
# voice agent is speaking in; these relays only carry an agent's click there,
# signed, and translate the answer into something the browser can act on.
#
# Everything about the destination is derived from the Pathors agent bot behind
# the call's inbox: its `outgoing_url` carries both the backend origin and the
# project id, and its webhook secret keys the request signature. There is no
# extra config surface to keep in sync.
#
# Subclasses name the endpoint (`#action`) and may extend the request body; the
# signing, transport and status mapping stay here so the endpoints cannot drift
# apart on the security-relevant parts.
class Pathors::VoiceRelay
  REQUEST_TIMEOUT = 10
  # Statuses the Pathors contract defines as meaningful to the browser; anything
  # else is an upstream malfunction and is collapsed into a 502. The backend
  # never answers 410 — the 410 the dashboard treats as "call already over"
  # comes from the calls controller's own `terminal?` check. If the backend
  # ever grows one, add it here or it will surface as a 502.
  RELAYED_STATUSES = [200, 404, 409].freeze
  NETWORK_ERRORS = [
    HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout, Timeout::Error,
    SocketError, OpenSSL::SSL::SSLError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, EOFError
  ].freeze

  Result = Struct.new(:status, :body, keyword_init: true) do
    def ok?
      status == 200
    end
  end

  def initialize(call:, user:)
    @call = call
    @user = user
  end

  def perform
    return misconfigured if endpoint.blank?

    relay(post_signed)
  rescue *NETWORK_ERRORS => e
    Rails.logger.warn "[Pathors] #{action} relay failed for call #{@call.id}: #{e.class} #{e.message}"
    Result.new(status: 502, body: { error: 'pathors_unreachable' })
  end

  private

  # The last path segment of the backend endpoint: `voice/<action>`.
  def action
    raise NotImplementedError, "#{self.class} must define #action"
  end

  def post_signed
    body = request_body
    timestamp = Time.current.to_i.to_s
    HTTParty.post(
      endpoint,
      body: body,
      headers: {
        'Content-Type' => 'application/json',
        'Accept' => 'application/json',
        'X-Pathors-Timestamp' => timestamp,
        'X-Pathors-Signature' => signature(timestamp, body)
      },
      timeout: REQUEST_TIMEOUT
    )
  end

  # The signed payload is this exact string — sign the serialized body so the
  # bytes we hash are the bytes that go on the wire.
  def request_body
    {
      # The signature covers the body but not the path, so naming the endpoint
      # here is what stops a join signed for one call being replayed as its
      # hang-up (and vice versa); the backend rejects a mismatch.
      action: action,
      sessionId: @call.provider_call_id,
      conversationId: @call.conversation.display_id,
      agent: { id: @user.id, name: @user.available_name },
      # Makes every signed body (and so every signature) unique, so a retry within
      # the same second is not rejected as a replay; the backend ignores the field.
      requestId: SecureRandom.uuid
    }.to_json
  end

  # The timestamp is folded into the MAC so a captured request cannot be
  # replayed with a fresh one: the backend rejects stale timestamps and
  # already-seen signatures, which only works if the two are bound together.
  def signature(timestamp, body)
    "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', webhook_secret.to_s, "#{timestamp}.#{body}")}"
  end

  # AgentBot#secret is the webhook signing secret; a bot whose secret is blank
  # falls back to its access token — the same pair the Pathors side stores.
  def webhook_secret
    agent_bot&.secret.presence || agent_bot&.access_token&.token
  end

  def relay(response)
    code = response.code.to_i
    return Result.new(status: code, body: parsed(response)) if RELAYED_STATUSES.include?(code)
    # 401 means our signature was rejected — a server-side misconfiguration, not
    # something the agent clicking the button can act on.
    return Result.new(status: 502, body: { error: 'pathors_auth_failed' }) if code == 401

    Rails.logger.warn "[Pathors] #{action} relay got unexpected status #{code} for call #{@call.id}"
    Result.new(status: 502, body: { error: 'pathors_error' })
  end

  def parsed(response)
    body = response.parsed_response
    body.is_a?(Hash) ? body : {}
  rescue StandardError
    {}
  end

  def misconfigured
    Result.new(status: 422, body: { error: 'pathors_not_configured' })
  end

  # "https://api.pathors.com/project/42/integration/chatwoot/callback"
  #   -> "https://api.pathors.com/project/42/integration/chatwoot/voice/<action>"
  def endpoint
    return @endpoint if defined?(@endpoint)

    @endpoint = build_endpoint
  end

  def build_endpoint
    project_id = agent_bot&.pathors_project_id
    return nil if project_id.blank?

    "#{agent_bot.pathors_origin}/project/#{project_id}/integration/chatwoot/voice/#{action}"
  end

  # An account can hold more than one Pathors bot — one per project — so the
  # account is too coarse a key to pick by: the wrong bot means the wrong
  # project id in the URL and the wrong secret on the signature, which the
  # backend answers with a 401. The inbox the call arrived on is bound to
  # exactly one bot, so that binding is the authoritative answer whenever it
  # points at Pathors. The account-wide scan stays as the fallback for inboxes
  # that were never bound (single-project installs, bots attached elsewhere).
  def agent_bot
    return @agent_bot if defined?(@agent_bot)

    fragment = Integrations::App::PATHORS_CALLBACK_URL_FRAGMENT
    inbox_bot = @call.inbox.agent_bot
    @agent_bot = if inbox_bot&.outgoing_url&.include?(fragment)
                   inbox_bot
                 else
                   @call.account.agent_bots.where('outgoing_url LIKE ?', "%#{fragment}%").order(:id).first
                 end
  end
end
