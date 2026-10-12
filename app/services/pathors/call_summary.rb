# The structured post-call summary the Pathors backend may send with a call's
# update: `{ intent?, result?, todos?: [String], warnings?: [String], text? }`.
# It is shown in the calls list, so long values are cut rather than refused —
# it is a generated artifact, and dropping a whole summary over one long line
# would lose more than it protects.
class Pathors::CallSummary
  TEXT_KEYS = %w[intent result text].freeze
  LIST_KEYS = %w[todos warnings].freeze
  MAX_TEXT_LENGTH = 500
  MAX_ITEMS = 10

  pattr_initialize :payload

  # nil when the payload has the documented shape, otherwise a message for the 422.
  def validation_error
    return 'summary must be an object' unless payload.is_a?(Hash)
    return 'summary intent, result and text must be strings' unless TEXT_KEYS.all? { |key| optional?(key, String) }
    return if LIST_KEYS.all? { |key| optional?(key, Array) && Array(payload[key]).all?(String) }

    'summary todos and warnings must be arrays of strings'
  end

  def to_h
    texts = TEXT_KEYS.index_with { |key| payload[key]&.truncate(MAX_TEXT_LENGTH) }
    lists = LIST_KEYS.index_with { |key| payload[key]&.first(MAX_ITEMS)&.map { |item| item.truncate(MAX_TEXT_LENGTH) } }
    texts.merge(lists).compact
  end

  private

  def optional?(key, type)
    payload[key].nil? || payload[key].is_a?(type)
  end
end
