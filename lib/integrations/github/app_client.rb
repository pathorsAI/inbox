# Talks to GitHub as the "Pathors Inbox" GitHub App. Nothing long-lived is stored:
# the app's private key signs a short JWT, which buys an installation token that
# expires within the hour, so an uninstall on GitHub cuts us off immediately.
class Integrations::Github::AppClient
  API_URL = 'https://api.github.com'.freeze
  OAUTH_TOKEN_URL = 'https://github.com/login/oauth/access_token'.freeze
  API_VERSION = '2022-11-28'.freeze
  PER_PAGE = 100
  TOKEN_REFRESH_MARGIN = 5.minutes
  # 422 is how the token endpoint says the requested repository is no longer
  # granted to the installation; every one of these needs the admin to reconnect.
  REAUTHORIZATION_STATUSES = [401, 403, 404, 422].freeze

  class Error < StandardError; end
  class AuthorizationError < Error; end

  def installation_token(installation_id, repository: nil)
    cache_key = ['github_app_installation_token', installation_id, repository&.downcase].compact.join(':')
    cached = Rails.cache.read(cache_key)
    return cached if cached.present?

    body = { repositories: [repository.split('/').last], permissions: { issues: 'write' } } if repository.present?
    response = HTTParty.post("#{API_URL}/app/installations/#{installation_id}/access_tokens",
                             headers: headers(app_jwt), body: body&.to_json)
    ensure_success!(response)

    expires_in = Time.zone.parse(response['expires_at']) - TOKEN_REFRESH_MARGIN - Time.current
    Rails.cache.write(cache_key, response['token'], expires_in: expires_in) if expires_in.positive?
    response['token']
  end

  def repositories(installation_id)
    paginate("#{API_URL}/installation/repositories", installation_token(installation_id), 'repositories')
      .pluck('full_name')
  end

  def exchange_code(code)
    response = HTTParty.post(OAUTH_TOKEN_URL,
                             headers: { 'Accept' => 'application/json' },
                             body: { client_id: config('GITHUB_APP_CLIENT_ID'), client_secret: config('GITHUB_APP_CLIENT_SECRET'), code: code })
    ensure_success!(response)
    # GitHub answers a bad or expired code with 200 and an `error` field.
    raise Error, "GitHub code exchange failed: #{response['error'] || response.code}" if response['access_token'].blank?

    response['access_token']
  end

  def user_installation_ids(user_token)
    paginate("#{API_URL}/user/installations", user_token, 'installations').pluck('id')
  end

  private

  def paginate(url, token, key)
    results = []
    next_url = "#{url}?per_page=#{PER_PAGE}"
    while next_url
      response = HTTParty.get(next_url, headers: headers(token))
      ensure_success!(response)
      results.concat(response[key])
      next_url = response.headers['link']&.match(/<([^>]+)>;\s*rel="next"/)&.captures&.first
    end
    results
  end

  def ensure_success!(response)
    return if response.success?

    error_class = REAUTHORIZATION_STATUSES.include?(response.code) ? AuthorizationError : Error
    raise error_class, "GitHub request to #{response.request.last_uri} failed: #{response.code} #{response.body}"
  end

  def app_jwt
    now = Time.current.to_i
    JWT.encode({ iss: config('GITHUB_APP_ID'), iat: now - 60, exp: now + 9.minutes.to_i },
               OpenSSL::PKey::RSA.new(config('GITHUB_APP_PRIVATE_KEY')), 'RS256')
  end

  def headers(token)
    {
      'Authorization' => "Bearer #{token}",
      'Accept' => 'application/vnd.github+json',
      'X-GitHub-Api-Version' => API_VERSION,
      'Content-Type' => 'application/json'
    }
  end

  def config(key)
    GlobalConfigService.load(key, nil)
  end
end
