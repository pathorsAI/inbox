# Records a CrmSyncEvent for the hook's sync log. Logging must never break a
# sync: a failed insert (including a missing table while a deploy runs ahead
# of its migration) is logged and dropped, inside a savepoint so a caller's
# transaction survives it.
module Crm::SyncLog
  module_function

  # contact: a Contact or a contact id
  def record(hook:, action:, status: 'success', contact: nil, message: nil, details: {}) # rubocop:disable Metrics/ParameterLists
    CrmSyncEvent.transaction(requires_new: true) do
      CrmSyncEvent.create!(
        account_id: hook.account_id, hook: hook, provider: hook.app_id, contact_id: contact.is_a?(Contact) ? contact.id : contact,
        action: action, status: status, message: message, details: details
      )
    end
  rescue StandardError => e
    Rails.logger.warn("[Crm::SyncLog] could not record #{action} for hook #{hook&.id}: #{e.class}: #{e.message}")
    nil
  end
end
