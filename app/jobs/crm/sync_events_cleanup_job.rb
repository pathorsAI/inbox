# Drops CRM sync log entries past their retention.
class Crm::SyncEventsCleanupJob < ApplicationJob
  queue_as :housekeeping

  def perform
    CrmSyncEvent.where(created_at: ...CrmSyncEvent::RETENTION.ago).in_batches(of: 5000).delete_all
  end
end
