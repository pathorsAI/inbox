class Api::V1::Accounts::Integrations::GithubController < Api::V1::Accounts::Integrations::BaseController
  include Github::IntegrationHelper

  before_action :check_authorization
  before_action :fetch_hook, except: [:create]

  # Completes an install that GitHub redirected through Github::CallbacksController.
  def create
    return render_connect_error('connection_failed') unless verify_github_state(params[:state]) == Current.account.id
    return render_connect_error('installation_not_verified') unless installation_visible_to_user?

    connect_installation
    render :update
  rescue Integrations::Github::AppClient::Error => e
    Rails.logger.error("GitHub connect failed for account #{Current.account.id}: #{e.message}")
    render_connect_error('connection_failed')
  end

  def repositories
    render json: installation_repositories
  rescue Integrations::Github::AppClient::AuthorizationError => e
    render_access_lost(e)
  end

  def update
    repository = installation_repositories.find { |name| name.casecmp?(params[:repository].to_s) }
    return render json: { error: I18n.t('integration_apps.github.errors.repository_not_granted') }, status: :unprocessable_entity if repository.blank?

    @hook.update!(settings: { 'repository' => repository, 'label' => params[:label].presence }.compact)
  rescue Integrations::Github::AppClient::AuthorizationError => e
    render_access_lost(e)
  end

  # Unbinds the installation from this account only. The app stays installed on
  # GitHub, where the organization may still use it for other accounts.
  def destroy
    @hook.destroy!
    head :ok
  end

  private

  def fetch_hook
    @hook = Current.account.hooks.find_by!(app_id: 'github')
  end

  def installation_id
    params[:installation_id].to_s
  end

  # `installation_id` arrives through a browser redirect, so anyone can put any id
  # there. Binding it unchecked would let one account open issues in another
  # organization's repositories. The user who just authorized must be able to see
  # the installation on GitHub's side.
  def installation_visible_to_user?
    return false if params[:code].blank? || installation_id.blank?

    user_token = app_client.exchange_code(params[:code])
    return true if app_client.user_installation_ids(user_token).map(&:to_s).include?(installation_id)

    Rails.logger.warn("GitHub connect for account #{Current.account.id} named installation #{installation_id}, which the authorizing user cannot see")
    false
  end

  def connect_installation
    @hook = Current.account.hooks.find_or_initialize_by(app_id: 'github')
    previous = @hook.settings.to_h
    settings = { 'label' => previous['label'] }
    settings['repository'] = previous['repository'] if repository_still_granted?(previous['repository'])

    @hook.update!(reference_id: installation_id, status: 'enabled', settings: settings.compact_blank)
    @hook.reauthorized!
  end

  def repository_still_granted?(repository)
    repository.present? && app_client.repositories(installation_id).any? { |name| name.casecmp?(repository) }
  end

  def installation_repositories
    @installation_repositories ||= app_client.repositories(@hook.reference_id)
  end

  def app_client
    @app_client ||= Integrations::Github::AppClient.new
  end

  def render_connect_error(reason)
    render json: { error: I18n.t("integration_apps.github.errors.#{reason}"), reason: reason }, status: :unprocessable_entity
  end

  def render_access_lost(error)
    Rails.logger.warn("GitHub installation #{@hook.reference_id} refused account #{Current.account.id}: #{error.message}")
    @hook.prompt_reauthorization!
    render json: { error: I18n.t('integration_apps.github.errors.access_lost') }, status: :unprocessable_entity
  end
end
