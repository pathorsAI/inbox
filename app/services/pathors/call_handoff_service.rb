# Posts the "AI handoff summary" card into a call's conversation when a human
# takes a Pathors voice call over: what the AI and the caller said, plus the
# variables the AI extracted, so the agent does not have to re-ask the caller.
#
# The card is an activity message on purpose: it never reaches the channel,
# webhooks, agent bots, automations, notifications or unread counts.
#
# One card per call. The created message id is kept on the call, so a retry or
# a second takeover returns the first card instead of posting another; the row
# lock keeps two concurrent requests from both creating one.
class Pathors::CallHandoffService
  ROLES = %w[user assistant].freeze
  MAX_TURNS = 500
  MAX_TURN_LENGTH = 4000
  MAX_VARIABLES = 100
  # Message validates `content` at this length; the plain-text fallback is cut
  # to fit, the card itself reads the full payload from content_attributes.
  MAX_CONTENT_LENGTH = 150_000
  I18N_SCOPE = 'conversations.messages.pathors_handoff'.freeze

  pattr_initialize [:call!, :payload!]

  # nil when the payload has the documented shape, otherwise a message for the 422.
  def validation_error
    transcript_error || variables_error || transferred_at_error || ai_duration_error
  end

  # Returns [message, created].
  def perform
    call.with_lock do
      existing = conversation.messages.find_by(id: call.handoff_message_id) if call.handoff_message_id.present?
      next [existing, false] if existing

      message = create_message
      call.update!(handoff_message_id: message.id)
      [message, true]
    end
  end

  private

  def conversation
    call.conversation
  end

  def create_message
    data = handoff_data
    conversation.messages.create!(
      account_id: call.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :activity,
      sender: nil,
      content: plain_text(data),
      content_type: 'pathors_handoff',
      content_attributes: { data: data }
    )
  end

  def handoff_data
    {
      transcript: payload[:transcript].map { |turn| turn.slice(:role, :content, :timestamp) },
      variables: payload[:variables],
      transferred_at: payload[:transferred_at],
      ai_duration_seconds: payload[:ai_duration_seconds]
    }.as_json
  end

  # For API consumers and the mobile app, which do not know the bubble.
  def plain_text(data)
    variable_lines = data['variables'].map { |key, value| "#{key}: #{variable_text(value)}" }
    transcript_lines = data['transcript'].map do |turn|
      "#{I18n.t("#{I18N_SCOPE}.roles.#{turn['role']}")}: #{turn['content']}"
    end

    [[I18n.t("#{I18N_SCOPE}.title")], variable_lines, transcript_lines]
      .reject(&:empty?)
      .map { |lines| lines.join("\n") }
      .join("\n\n")
      .truncate(MAX_CONTENT_LENGTH)
  end

  def variable_text(value)
    return I18n.t("#{I18N_SCOPE}.not_captured") if value.nil? || value == ''
    return value.to_json if value.is_a?(Hash) || value.is_a?(Array)

    value.to_s
  end

  def transcript_error
    transcript = payload[:transcript]
    return 'transcript must be an array' unless transcript.is_a?(Array)
    return "transcript must have at most #{MAX_TURNS} turns" if transcript.size > MAX_TURNS

    return if transcript.all? { |turn| valid_turn?(turn) }

    "each transcript turn needs role user or assistant, string content of at most #{MAX_TURN_LENGTH} chars " \
      'and an optional ISO-8601 timestamp'
  end

  def valid_turn?(turn)
    turn.is_a?(Hash) &&
      ROLES.include?(turn[:role]) &&
      turn[:content].is_a?(String) && turn[:content].length <= MAX_TURN_LENGTH &&
      (turn[:timestamp].nil? || iso8601?(turn[:timestamp]))
  end

  def variables_error
    variables = payload[:variables]
    return 'variables must be an object' unless variables.is_a?(Hash)

    "variables must have at most #{MAX_VARIABLES} keys" if variables.size > MAX_VARIABLES
  end

  def transferred_at_error
    'transferred_at must be an ISO-8601 timestamp' unless iso8601?(payload[:transferred_at])
  end

  def ai_duration_error
    value = payload[:ai_duration_seconds]
    return if value.nil? || (value.is_a?(Integer) && value >= 0)

    'ai_duration_seconds must be a non-negative integer'
  end

  def iso8601?(value)
    value.is_a?(String) && Time.iso8601(value).present?
  rescue ArgumentError
    false
  end
end
