# GitHub sends the browser here after an install. Nothing is bound yet: the
# settings page posts `code`, `installation_id` and `state` back from inside the
# admin's authenticated session (Integrations::GithubController#create). Binding
# here instead would let an admin of one account hand their `state` to an org
# owner elsewhere and capture that org's installation when the owner installs.
class Github::CallbacksController < ApplicationController
  include Github::IntegrationHelper

  def show
    account_id = verify_github_state(params[:state])
    return redirect_expired_state if account_id.blank?

    query = if params[:setup_action] == 'request'
              # An org member without admin rights only *requested* the install;
              # GitHub waits for an org owner, and nothing is installed yet.
              { setup_action: 'request' }
            else
              params.permit(:code, :installation_id, :state).to_h
            end
    redirect_to settings_url(account_id, query)
  end

  private

  # The install itself may already have finished on GitHub, so the admin is
  # told to press Connect again rather than dropped on the app root.
  def redirect_expired_state
    account_id = expired_github_state_account_id(params[:state])
    return redirect_to(frontend_url) if account_id.blank?

    redirect_to settings_url(account_id, { error: 'state_expired' })
  end

  def settings_url(account_id, query)
    "#{frontend_url}/app/accounts/#{account_id}/settings/integrations/github?#{query.to_query}"
  end

  def frontend_url
    ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
  end
end
