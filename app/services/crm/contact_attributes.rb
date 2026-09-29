# The CRM fields shown on contacts (list column, filters, sidebar attributes),
# stored as ordinary contact custom attributes so Chatwoot's own filtering,
# display and export work on them. Generic across CRMs: each integration
# writes the same crm_* keys. Values belong to the CRM; an edit made in the
# Inbox is overwritten on the next sync.
#
# Writing them does not echo back to the CRM: Crm::Twenty::ProcessorService
# ignores contact.updated events that only change custom_attributes.
module Crm::ContactAttributes
  DEFINITIONS = {
    'crm_status' => :list,
    'crm_provider' => :text,
    'crm_job_title' => :text,
    'crm_stage' => :text,
    'crm_opportunity' => :text,
    'crm_owner' => :text,
    'crm_url' => :link,
    'crm_synced_at' => :date
  }.freeze
  # Fixed order: the stored value is the label at the status's index.
  STATUSES = %i[linked needs_attention unlinked].freeze
  FIELDS = DEFINITIONS.keys.map { |key| key.delete_prefix('crm_').to_sym }.freeze

  @ensured = Concurrent::Set.new

  module_function

  # Creates whichever definitions the account is missing, named in its locale.
  # Checked once per process per account.
  def ensure_definitions!(account)
    return if @ensured.include?(account.id)

    definitions = account.custom_attribute_definitions.contact_attribute
    missing = DEFINITIONS.keys - definitions.where(attribute_key: DEFINITIONS.keys).pluck(:attribute_key)
    I18n.with_locale(account.locale) { missing.each { |key| create_definition(definitions, key) } }
    @ensured << account.id
  end

  # Sets the given fields (provider:, status:, job_title:, stage:, opportunity:,
  # owner:, url:, synced_at:); a blank value removes the key, an omitted one is
  # left as it is. status is one of STATUSES. Saves only on a change, and
  # returns the keys that changed.
  def write(contact, **values)
    unknown = values.keys - FIELDS
    raise ArgumentError, "Unknown CRM attributes #{unknown}" if unknown.any?

    ensure_definitions!(contact.account)
    current = contact.custom_attributes || {}
    stored = stored_values(contact.account, values)
    updated = current.except(*stored.select { |_, value| value.blank? }.keys).merge(stored.compact_blank)
    changed = (current.keys | updated.keys).reject { |key| current[key] == updated[key] }
    return changed if changed.empty?

    # Only these keys change; a contact whose other data no longer passes
    # validation (older imports) must still show its CRM state.
    contact.custom_attributes = updated
    contact.save!(validate: false)
    changed
  end

  # Unlinked: only the status (and who says so) stays.
  def clear(contact, provider:, status: :unlinked)
    write(contact, **FIELDS.index_with(nil), provider: provider, status: status)
  end

  def stored_values(account, values)
    values.to_h do |field, value|
      value = status_label(account, value) if field == :status
      value = value&.iso8601 if field == :synced_at
      ["crm_#{field}", value]
    end
  end

  def status_label(account, status)
    return if status.nil?

    index = STATUSES.index(status) || raise(ArgumentError, "Unknown CRM status #{status}")
    definition = account.custom_attribute_definitions.contact_attribute.find_by(attribute_key: 'crm_status')
    if definition.nil?
      # Deleted since this process ensured it.
      @ensured.delete(account.id)
      ensure_definitions!(account)
      definition = account.custom_attribute_definitions.contact_attribute.find_by!(attribute_key: 'crm_status')
    end
    definition.attribute_values[index]
  end

  def create_definition(definitions, key)
    definitions.create!(
      attribute_key: key,
      attribute_display_type: DEFINITIONS[key],
      attribute_display_name: I18n.t("crm.contact_attributes.names.#{key}"),
      attribute_description: I18n.t('crm.contact_attributes.description'),
      attribute_values: key == 'crm_status' ? STATUSES.map { |status| I18n.t("crm.contact_attributes.statuses.#{status}") } : []
    )
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    # Another process created it first.
    raise unless definitions.exists?(attribute_key: key)
  end
end
