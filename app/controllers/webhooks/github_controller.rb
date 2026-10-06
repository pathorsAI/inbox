class Webhooks::GithubController < ActionController::API
  before_action :verify_signature!

  def events
    case request.headers['X-GitHub-Event']
    when 'installation'
      handle_installation
    when 'installation_repositories'
      handle_repositories_removed
    end

    head :ok
  end

  private

  def verify_signature!
    secret = GlobalConfigService.load('GITHUB_APP_WEBHOOK_SECRET', nil)
    signature = request.headers['X-Hub-Signature-256']
    return head :unauthorized if secret.blank? || signature.blank?

    expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, request.raw_post)}"
    head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(expected, signature)
  end

  def handle_installation
    case payload['action']
    when 'deleted', 'suspend'
      installation_hooks.find_each(&:prompt_reauthorization!)
    when 'unsuspend'
      installation_hooks.find_each(&:reauthorized!)
    end
  end

  def handle_repositories_removed
    removed = Array(payload['repositories_removed']).map { |repository| repository['full_name'].downcase }
    return if removed.empty?

    installation_hooks.find_each do |hook|
      hook.prompt_reauthorization! if removed.include?(hook.settings['repository']&.downcase)
    end
  end

  def installation_hooks
    Integrations::Hook.where(app_id: 'github', reference_id: payload.dig('installation', 'id').to_s)
  end

  # Parsed from the raw body because Rails reserves params[:action] for the
  # controller action, which would hide the GitHub event's own `action`.
  def payload
    @payload ||= JSON.parse(request.raw_post)
  end
end
