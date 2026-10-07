require 'omniauth-oauth2'

# Sign in with a Pathors account. Pathors' OAuth server issues no id_token, so
# the identity comes from /oauth/userinfo. client_id, client_secret and site are
# filled per request by the setup lambda in config/initializers/omniauth.rb.
class OmniAuth::Strategies::Pathors < OmniAuth::Strategies::OAuth2
  option :name, 'pathors'
  option :scope, 'openid email profile'
  option :pkce, true
  option :client_options, authorize_url: '/oauth/authorize', token_url: '/oauth/token'

  uid { raw_info['sub'] }

  # email_verified sits in info rather than extra: devise_token_auth drops
  # `extra` before handing the auth hash to the callback controller.
  info do
    {
      email: raw_info['email'],
      name: raw_info['name'],
      image: raw_info['picture'],
      email_verified: raw_info['email_verified']
    }
  end

  def raw_info
    @raw_info ||= access_token.get('/oauth/userinfo').parsed
  end

  # The base callback_url carries the callback's own query string, which
  # would no longer match the redirect_uri sent to /oauth/authorize.
  def callback_url
    full_host + callback_path
  end
end
