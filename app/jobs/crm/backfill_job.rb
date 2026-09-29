# Goes through an account's contacts once for a CRM hook: linked contacts get
# their CRM attributes refreshed, the rest are matched to an existing CRM
# record. Nothing is created in the CRM. Paced to about 20 contacts a minute,
# since the CRM's API rate limit is shared with live syncing (Twenty: 100
# requests a minute per workspace). Started by the crm_backfill endpoint,
# which has already claimed the run (Crm::BackfillProgress#start!).
class Crm::BackfillJob < ApplicationJob
  queue_as :low

  PAUSE = 3.seconds
  RATE_LIMIT_PAUSE = 60.seconds
  RATE_LIMIT_ATTEMPTS = 5
  LOCK_ATTEMPTS = 10

  def perform(hook)
    progress = Crm::BackfillProgress.new(hook)
    provider = Crm::Providers.for(hook)
    Crm::SyncLog.record(hook: hook, action: 'backfill_started', details: { total: progress.status['total'] })
    begin
      provider.backfill_scope.find_each do |contact|
        break unless Integrations::Hook.enabled.exists?(hook.id)

        progress.advance(backfill(hook, provider, contact))
        sleep PAUSE
      end
    ensure
      progress.finish!
      Crm::SyncLog.record(hook: hook, action: 'backfill_finished', details: progress.counts)
    end
  end

  private

  # The counter the contact adds to, or nil when a live sync held it throughout.
  def backfill(hook, provider, contact)
    rate_limits = 0
    begin
      with_contact_lock(hook, contact) { provider.backfill(contact).to_s }
    rescue StandardError => e
      if provider.rate_limited?(e) && (rate_limits += 1) < RATE_LIMIT_ATTEMPTS
        Crm::SyncLog.record(hook: hook, action: 'rate_limited', status: 'failure', contact: contact, message: e.message,
                            details: { source: 'backfill', attempt: rate_limits })
        sleep RATE_LIMIT_PAUSE
        retry
      end
      Crm::SyncLog.record(hook: hook, action: 'failed', status: 'failure', contact: contact, message: e.message,
                          details: { source: 'backfill', error_class: e.class.name })
      'errors'
    end
  end

  # The lock HookJob takes, so a backfill and a live sync never match the same contact at once.
  def with_contact_lock(hook, contact)
    key = format(::Redis::Alfred::CRM_CONTACT_PROCESS_MUTEX, hook_id: hook.id, contact_id: contact.id)
    lock_manager = Redis::LockManager.new
    acquired = false
    LOCK_ATTEMPTS.times do
      break if (acquired = lock_manager.lock(key, 30.seconds))

      sleep 1
    end
    return unless acquired

    begin
      yield
    ensure
      lock_manager.unlock(key)
    end
  end
end
