class HookPolicy < ApplicationPolicy
  def create?
    @account_user.administrator?
  end

  def auth?
    create?
  end

  def complete_install?
    create?
  end

  def update?
    @account_user.administrator?
  end

  def process_event?
    true
  end

  def destroy?
    @account_user.administrator?
  end

  # GitHub App repository picker (Integrations::GithubController)
  def repositories?
    @account_user.administrator?
  end

  # CRM sync log and backfill (Integrations::CrmSyncController)
  def sync_events?
    @account_user.administrator?
  end

  def backfill_status?
    @account_user.administrator?
  end

  def start_backfill?
    @account_user.administrator?
  end
end
