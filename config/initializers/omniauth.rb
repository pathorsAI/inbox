# OmniAuth configuration
# Sets the full host URL for callbacks and proper redirect handling
OmniAuth.config.full_host = ENV.fetch('FRONTEND_URL', 'http://localhost:3000')

require Rails.root.join('lib/omniauth/strategies/pathors').to_s

Rails.application.config.middleware.use OmniAuth::Builder do
  # Read on every request so a super admin edit applies without a restart. With
  # the switch off both phases 404: `omniauth.error.app` makes OmniAuth re-raise
  # instead of turning the error into a login failure redirect.
  provider :pathors, setup: lambda { |env|
    unless Pathors::Login.enabled?
      env['omniauth.error.app'] = true
      raise ActionController::RoutingError, 'Not Found'
    end

    strategy = env['omniauth.strategy']
    strategy.options.client_id = Pathors::Login.client_id
    strategy.options.client_secret = Pathors::Login.client_secret
    strategy.options.client_options.site = Pathors::Login.api_url
  }
end

# Devise's failure handler would send a cancelled or failed Pathors sign-in to
# the generic "access denied" message; name the cause on the login page instead.
# Devise installs its handler when the first omniauthable model loads; load it
# now so it is the one wrapped here rather than replacing this one later.
require 'devise/omniauth'
devise_on_failure = OmniAuth.config.on_failure
OmniAuth.config.on_failure = lambda do |env|
  next devise_on_failure.call(env) unless env['omniauth.error.strategy']&.name.to_s == 'pathors'

  [302, { 'Location' => "#{ENV.fetch('FRONTEND_URL', '')}/app/login?error=pathors-login-failed" }, []]
end
