# A CRM hook's sync log and match-all backfill, for its settings page. Generic
# across CRMs (Crm::Providers); admin only, like managing the hook.
class Api::V1::Accounts::Integrations::CrmSyncController < Api::V1::Accounts::Integrations::BaseController
  EVENTS_PER_PAGE = 25

  before_action :check_authorization
  before_action :fetch_hook

  def sync_events
    status = params[:status].presence
    return render json: { error: 'invalid_status' }, status: :unprocessable_entity if status && CrmSyncEvent::STATUSES.exclude?(status)

    page = [params[:page].to_i, 1].max
    records = events_page(status ? events.where(status: status) : events, page)
    render json: {
      summary: summary,
      events: records.first(EVENTS_PER_PAGE).map { |event| present_event(event) },
      meta: { page: page, has_more: records.size > EVENTS_PER_PAGE }
    }
  end

  def backfill_status
    render json: progress.status
  end

  def start_backfill
    return render json: { error: 'hook_disabled' }, status: :unprocessable_entity unless @hook.enabled?
    return render json: { error: 'already_running' }, status: :conflict unless progress.start!(provider.backfill_scope.count)

    Crm::BackfillJob.perform_later(@hook)
    render json: progress.status, status: :accepted
  end

  private

  def fetch_hook
    @hook = Current.account.hooks.find(params[:id])
    raise ActiveRecord::RecordNotFound unless Crm::Providers.supported?(@hook)
  end

  def provider
    @provider ||= Crm::Providers.for(@hook)
  end

  def progress
    @progress ||= Crm::BackfillProgress.new(@hook)
  end

  def events
    CrmSyncEvent.where(hook_id: @hook.id)
  end

  # One more than a page, to tell whether another follows.
  def events_page(scope, page)
    scope.includes(:contact).order(created_at: :desc, id: :desc).offset((page - 1) * EVENTS_PER_PAGE).limit(EVENTS_PER_PAGE + 1).to_a
  end

  def summary
    recent = events.where(created_at: 24.hours.ago..)
    {
      last_success_at: events.where(status: 'success').maximum(:created_at)&.utc&.iso8601,
      last_24h: {
        success: recent.where(status: 'success').count,
        failure: recent.where(status: 'failure').where.not(action: 'rate_limited').count,
        rate_limited: recent.where(action: 'rate_limited').count
      },
      pending_conflicts: provider.pending_conflicts
    }
  end

  def present_event(event)
    {
      id: event.id,
      action: event.action,
      status: event.status,
      message: event.message,
      details: event.details,
      contact: event.contact && { id: event.contact.id, name: event.contact.name },
      created_at: event.created_at.utc.iso8601
    }
  end
end
