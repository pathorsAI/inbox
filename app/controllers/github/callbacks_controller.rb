# GitHub sends the browser here after an install. Nothing is bound yet: the
# settings page posts `code`, `installation_id` and `state` back from inside the
# admin's authenticated session (Integrations::GithubController#create). Binding
# here instead would let an admin of one account hand their `state` to an org
# owner elsewhere and capture that org's installation when the owner installs.
class Github::CallbacksController < ApplicationController
  include Github::IntegrationHelper

  def show
    account_id = verify_github_state(params[:state])
    return redirect_to(frontend_url) if account_id.blank?

    query = if params[:setup_action] == 'request'
              # An org member without admin rights only *requested* the install;
              # GitHub waits for an org owner, and nothing is installed yet.
              { setup_action: 'request' }
            else
              params.permit(:code, :installation_id, :state).to_h
            end
    redirect_to "#{frontend_url}/app/accounts/#{account_id}/settings/integrations/github?#{query.to_query}"
  end

  private

  def frontend_url
    ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
  end
end
