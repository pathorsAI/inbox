# The conversation sidebar's view of a contact in Twenty. Open to agents: they
# read the card and may add a missing contact to Twenty, but only admins manage
# the hook itself (through the generic hooks endpoints).
class Api::V1::Accounts::Integrations::TwentyController < Api::V1::Accounts::Integrations::BaseController
  LOCK_ATTEMPTS = 5

  before_action :fetch_hook, :fetch_contact

  rescue_from Crm::Twenty::Api::Client::ApiError do |error|
    Rails.logger.warn("Twenty request failed for hook #{@hook&.id}: #{error.message}")
    render json: { error: 'twenty_unavailable' }, status: :bad_gateway
  end

  def person
    render json: card_service.perform
  end

  def create_person
    return render json: { error: I18n.t('errors.twenty.contact_not_identifiable') }, status: :unprocessable_entity unless identifiable?

    # Same lock as the sync jobs, so a click racing a job cannot create the person twice.
    with_contact_lock { render json: card_service.perform(create: true) }
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
    @contact.email.present? || @contact.phone_number.present?
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
