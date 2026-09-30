# The conversation sidebar's view of a contact in Twenty. Open to agents: they
# read the card and may add a missing contact to Twenty, but only admins manage
# the hook itself (through the generic hooks endpoints).
class Api::V1::Accounts::Integrations::TwentyController < Api::V1::Accounts::Integrations::BaseController
  LOCK_ATTEMPTS = 5
  CONFLICTS_PER_PAGE = 25

  before_action :fetch_hook
  before_action :fetch_contact, except: [:conflicts]

  rescue_from Crm::Twenty::Api::Client::ApiError do |error|
    Rails.logger.warn("Twenty request failed for hook #{@hook&.id}: #{error.message}")
    render json: { error: 'twenty_unavailable' }, status: :bad_gateway
  end

  # Declared after ApiError so it wins: a throttled request is "try again shortly", not an outage.
  rescue_from Crm::Twenty::Api::Client::RateLimitError do
    render json: { error: 'twenty_rate_limited' }, status: :too_many_requests
  end

  rescue_from Crm::Twenty::ConflictResolver::Error, ActiveRecord::RecordInvalid do |error|
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def person
    render json: card_service.perform
  end

  def create_person
    return render json: { error: I18n.t('errors.twenty.contact_not_identifiable') }, status: :unprocessable_entity unless identifiable?

    # Same lock as the sync jobs, so a click racing a job cannot create the person twice.
    with_contact_lock { render json: card_service.perform(create: true) }
  end

  # Contacts whose Inbox and Twenty records disagree, newest first.
  def conflicts
    scope = Current.account.contacts.where(
      "jsonb_array_length(COALESCE(contacts.additional_attributes #> '{external,twenty_conflicts}', '[]'::jsonb)) > 0"
    )
    contacts = scope.order(updated_at: :desc).page(params[:page]).per(CONFLICTS_PER_PAGE)
    render json: {
      count: scope.count,
      contacts: contacts.map do |contact|
        { id: contact.id, name: contact.name, email: contact.email, phone_number: contact.phone_number, thumbnail: contact.avatar_url,
          conflicts: Crm::Twenty::Conflicts.new(contact).stored }
      end
    }
  end

  def resolve_conflict
    resolver = Crm::Twenty::ConflictResolver.new(hook: @hook, contact: @contact)
    options = params.permit(:field, :person_id, :other_contact_id).to_h.symbolize_keys
    with_contact_lock do
      render json: resolver.perform(type: params.require(:type), choice: params.require(:choice), **options)
    end
  end

  private

  def fetch_hook
    @hook = Current.account.hooks.enabled.find_by!(app_id: 'twenty')
  end

  def fetch_contact
    @contact = Current.account.contacts.find(params[:contact_id])
  end

  def card_service
    Crm::Twenty::PersonCardService.new(hook: @hook, contact: @contact)
  end

  def identifiable?
    Crm::Twenty::PersonMapper.new(@contact).matchable?
  end

  def with_contact_lock
    key = format(::Redis::Alfred::CRM_CONTACT_PROCESS_MUTEX, hook_id: @hook.id, contact_id: @contact.id)
    lock_manager = Redis::LockManager.new
    acquired = false
    LOCK_ATTEMPTS.times do
      break if (acquired = lock_manager.lock(key, 30.seconds))

      sleep 0.5
    end
    return render json: { error: 'twenty_busy' }, status: :conflict unless acquired

    begin
      yield
    ensure
      lock_manager.unlock(key)
    end
  end
end
