# The conversation attributes Pathors::CallLifecycleService writes onto a call's
# conversation. Defining them is what makes them show up — labelled, typed and
# filterable — in the conversation sidebar, filters and reports instead of as
# raw keys. Provisioned with every new voice inbox and, for accounts that had
# one before, lazily on the next call (see Pathors::CallsController#create).
#
# An existing definition with the same key wins as-is: an admin may have
# renamed or retyped it, and that is theirs to keep.
module Pathors::CallAttributeDefinitions
  DEFINITIONS = [
    { attribute_key: 'pathors_call_from', attribute_display_name: '來電號碼', attribute_display_type: :text },
    { attribute_key: 'pathors_call_outcome', attribute_display_name: '通話結果', attribute_display_type: :list,
      attribute_values: Pathors::CallLifecycleService::OUTCOMES },
    { attribute_key: 'pathors_takeover_requested', attribute_display_name: 'AI 請求過支援', attribute_display_type: :checkbox }
  ].freeze

  # Accounts whose voice inboxes predate the provisioning get the definitions
  # on their next call; the cache keeps the lookup off every later one.
  #
  # Never raises: it runs inside the call create the Pathors backend is
  # waiting on, and a failure costs only the labels. Nothing is cached on
  # failure, so the next call tries again.
  def self.ensure_once!(account)
    Rails.cache.fetch("pathors:call-attr-defs:v1:#{account.id}", expires_in: 1.day) do
      ensure!(account)
      true
    end
  rescue StandardError => e
    Rails.logger.error("Pathors call attribute definitions failed for account #{account.id}: #{e.class}: #{e.message}")
    false
  end

  def self.ensure!(account)
    DEFINITIONS.each do |definition|
      account.custom_attribute_definitions
             .create_with(definition.except(:attribute_key))
             .find_or_create_by!(attribute_key: definition[:attribute_key], attribute_model: :conversation_attribute)
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      # A concurrent call created it first (the unique index, or the uniqueness
      # validation seeing the other row mid-race); it exists, which is all this wants.
      next
    end
  end
end
