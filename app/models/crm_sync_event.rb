# == Schema Information
#
# Table name: crm_sync_events
#
#  id         :bigint           not null, primary key
#  action     :string           not null
#  details    :jsonb            not null
#  message    :text
#  provider   :string           not null
#  status     :string           not null
#  created_at :datetime         not null
#  account_id :bigint           not null
#  contact_id :bigint
#  hook_id    :bigint           not null
#
# Indexes
#
#  index_crm_sync_events_on_hook_id_and_created_at             (hook_id,created_at DESC)
#  index_crm_sync_events_on_hook_id_and_status_and_created_at  (hook_id,status,created_at DESC)
#

# What a CRM integration did, for the hook's sync log in settings (written
# through Crm::SyncLog, kept for RETENTION).
class CrmSyncEvent < ApplicationRecord
  ACTIONS = %w[
    linked created_person filled_fields note_synced note_deleted conversation_logged conflict_raised conflict_resolved
    attributes_refreshed failed rate_limited backfill_started backfill_finished
  ].freeze
  STATUSES = %w[success failure].freeze
  RETENTION = 90.days

  belongs_to :account
  belongs_to :hook, class_name: 'Integrations::Hook'
  belongs_to :contact, optional: true

  validates :provider, presence: true
  validates :action, inclusion: { in: ACTIONS }
  validates :status, inclusion: { in: STATUSES }
end
