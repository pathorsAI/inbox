# Pathors-initiated connect (fork feature).
#
# The integration page connects the account it is opened in. This flow starts
# on the Pathors side instead: the organization is known, the Chatwoot account
# is not, and the user may belong to several. So these endpoints are scoped to
# the signed-in user rather than an account. They list the accounts the user
# administers, and hand off to the same Pathors authorize request the
# integration page builds — with the organization added as a signed claim so
# Pathors can lock its consent page to it.
#
# Chatwoot decides who may connect an account (an administrator of it); Pathors
# decides who may bind the organization. Neither trusts the other's page.
class Api::V1::Pathors::ConnectionsController < Api::BaseController
  include Pathors::IntegrationHelper

  UUID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  before_action :validate_organization_id, only: [:create, :create_account]
  before_action :ensure_pathors_configured, only: [:create, :create_account]

  def show
    accounts = administered_accounts.includes(:hooks).order(:name)
    connected_ids = pathors_bots.where(account_id: accounts.select(:id)).distinct.pluck(:account_id)

    render json: {
      can_create_account: account_creation_enabled?,
      accounts: accounts.map do |account|
        {
          id: account.id,
          name: account.name,
          connected: connected_ids.include?(account.id),
          organization_id: pathors_hook(account)&.settings.to_h['organization_id']
        }
      end
    }
  end

  def create
    account = administered_accounts.find_by(id: params[:account_id])
    return render_forbidden(I18n.t('errors.pathors.connect.account_forbidden')) if account.blank?
    return render_could_not_create_error(I18n.t('errors.pathors.connect.connected_to_other_organization')) if bound_elsewhere?(account)

    render json: { authorize_url: pathors_authorize_url(account, organization_id: params[:organization_id]) }
  end

  # A new account for this user, created only to be connected right away. Same
  # outcome as the dashboard's "new account" (AccountBuilder, the user as its
  # administrator), but behind its own switch: new Pathors customers get their
  # account here even where the dashboard-wide CREATE_NEW_ACCOUNT_FROM_DASHBOARD
  # and public signup are off.
  def create_account
    return render_forbidden(I18n.t('errors.pathors.connect.account_creation_disabled')) unless account_creation_enabled?

    account_name = params[:account_name].to_s.strip
    return render_could_not_create_error(I18n.t('errors.pathors.connect.account_name_required')) if account_name.blank?

    _user, account = AccountBuilder.new(account_name: account_name, email: Current.user.email, user: Current.user).perform

    render json: {
      account_id: account.id,
      authorize_url: pathors_authorize_url(account, organization_id: params[:organization_id])
    }
  end

  private

  def administered_accounts
    Current.user.accounts.active.where(account_users: { role: AccountUser.roles[:administrator] })
  end

  # Connected means the Pathors agent bot is there, the same test the
  # integration page uses. A hook without a bot is an unfinished connect the
  # integration page offers to retry, so it does not hold the account.
  def pathors_bots
    AgentBot.where('outgoing_url LIKE ?', "%#{Integrations::App::PATHORS_CALLBACK_URL_FRAGMENT}%")
  end

  def pathors_hook(account)
    account.hooks.find { |hook| hook.app_id == 'pathors' }
  end

  # Reconnecting to the same organization is allowed; anything else would take
  # the account away from the organization it serves, so the user has to
  # disconnect it on that account's integration page first. A connection made
  # before organization-wide binding carries no organization and counts as
  # bound elsewhere.
  def bound_elsewhere?(account)
    return false unless pathors_bots.exists?(account_id: account.id)

    account.hooks.find_by(app_id: 'pathors')&.settings.to_h['organization_id'] != params[:organization_id]
  end

  # On unless an operator turns it off (installation config or ENV), like the
  # other PATHORS_* settings.
  def account_creation_enabled?
    ActiveModel::Type::Boolean.new.cast(GlobalConfigService.load('PATHORS_CONNECT_ALLOW_ACCOUNT_CREATION', 'true'))
  end

  def validate_organization_id
    return if UUID_FORMAT.match?(params[:organization_id].to_s)

    render_could_not_create_error(I18n.t('errors.pathors.connect.invalid_organization_id'))
  end

  def ensure_pathors_configured
    return if GlobalConfigService.load('PATHORS_OAUTH_CLIENT_ID', nil).present? &&
              GlobalConfigService.load('PATHORS_CONNECT_STATE_SECRET', nil).present?

    render_could_not_create_error(I18n.t('errors.pathors.connect.unavailable'))
  end

  def render_forbidden(message)
    render json: { error: message }, status: :forbidden
  end
end
