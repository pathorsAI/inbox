# The CRM integrations that share the generic CRM features (contact
# attributes, sync log, match-all backfill), by hook app_id. Each adapter
# answers:
#   pending_conflicts   contacts waiting on a person to settle a disagreement
#   backfill_scope      contacts a backfill goes through
#   backfill(contact)   links or refreshes one contact, never creating a CRM record;
#                       returns :linked, :refreshed, :ambiguous or :no_match
#   rate_limited?(error)
module Crm::Providers
  ADAPTERS = { 'twenty' => 'Crm::Twenty::Provider' }.freeze

  def self.supported?(hook)
    ADAPTERS.key?(hook.app_id)
  end

  def self.for(hook)
    ADAPTERS.fetch(hook.app_id).constantize.new(hook)
  end
end
