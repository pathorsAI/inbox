class Contacts::FilterService < FilterService
  ATTRIBUTE_MODEL = 'contact_attribute'.freeze

  def initialize(account, user, params)
    @account = account
    # TODO: Change the order of arguments in FilterService maybe?
    # account, user, params makes more sense
    super(params, user)
  end

  def perform
    validate_query_operator
    @contacts = query_builder(@filters['contacts'])

    {
      contacts: @contacts,
      count: @contacts.count
    }
  end

  def filter_values(query_hash)
    current_val = query_hash['values'][0]
    if query_hash['attribute_key'] == 'phone_number'
      "+#{current_val&.delete('+')}"
    elsif query_hash['attribute_key'] == 'country_code'
      current_val.downcase
    else
      current_val.is_a?(String) ? current_val.downcase : current_val
    end
  end

  def base_relation
    @account.contacts.resolved_contacts(use_crm_v2: @account.feature_enabled?('crm_v2'))
  end

  def filter_config
    {
      entity: 'Contact',
      table_name: 'contacts'
    }
  end

  private

  # Fork: contacts linked to a Twenty person, with sync conflicts waiting, or
  # not linked (see Crm::Twenty::Linker and Crm::Twenty::Conflicts).
  TWENTY_STATUS_CONDITIONS = {
    'linked' => "contacts.additional_attributes #>> '{external,twenty_id}' IS NOT NULL",
    'needs_attention' => "jsonb_array_length(COALESCE(contacts.additional_attributes #> '{external,twenty_conflicts}', '[]'::jsonb)) > 0",
    'unlinked' => "contacts.additional_attributes #>> '{external,twenty_id}' IS NULL"
  }.freeze

  PRESENCE_OPERATORS = %w[is_present is_not_present].freeze
  BLANKABLE_ATTRIBUTES = %w[email phone_number].freeze

  def build_condition_query_string(current_filter, query_hash, current_index)
    return twenty_status_condition(query_hash) if query_hash['attribute_key'] == 'twenty_status'
    return presence_condition(query_hash) if blankable_presence?(query_hash)

    super
  end

  def twenty_status_condition(query_hash)
    condition = TWENTY_STATUS_CONDITIONS.fetch(Array(query_hash['values']).first.to_s) do
      raise CustomExceptions::CustomFilter::InvalidValue.new(attribute_name: 'twenty_status')
    end
    condition = "NOT (#{condition})" if query_hash[:filter_operator] == 'not_equal_to'
    "(#{condition}) #{query_hash[:query_operator]}"
  end

  # A cleared phone number is kept as '' rather than NULL, so "has a phone"
  # means non-blank, not merely non-null.
  def blankable_presence?(query_hash)
    BLANKABLE_ATTRIBUTES.include?(query_hash['attribute_key']) && PRESENCE_OPERATORS.include?(query_hash[:filter_operator])
  end

  def presence_condition(query_hash)
    operator = query_hash[:filter_operator] == 'is_present' ? 'IS NOT NULL' : 'IS NULL'
    "NULLIF(contacts.#{query_hash['attribute_key']}, '') #{operator} #{query_hash[:query_operator]}"
  end

  def equals_to_filter_string(filter_operator, current_index)
    return "= :value_#{current_index}" if filter_operator == 'equal_to'

    "!= :value_#{current_index}"
  end
end
