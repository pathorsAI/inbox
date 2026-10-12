# Stores what the Pathors voice agent is doing on a live call — turn and
# interruption counts, whether a transfer failed, a window of the transcript,
# and what needs a human's attention (the AI asking for help, a transfer in
# flight, the human leaving) — so agents can follow the call in the dashboard
# before anyone takes it over. What that attention means for the call and its
# conversation is decided by Pathors::CallLifecycleService, run on every stored
# update before the broadcast.
#
# The backend pushes the whole state on every turn, and deliveries can arrive
# out of order. `seq` (monotonic per call) decides which one wins: an update no
# newer than the stored one, or one for a call that already ended, is dropped.
# The row lock keeps two concurrent deliveries from both passing that check.
#
# Nothing here becomes a chat message, and the voice_call message is not
# touched: a message event would also reach the contact's widget, account
# webhooks and the inbox's agent bot on every turn. A stored update is
# broadcast as pathors_call.live_updated to the inbox's agents and the account
# administrators only (ActionCableListener), through the sync dispatcher alone,
# so no async listener (webhooks, automations) ever sees it.
class Pathors::CallLiveStateService
  KINDS = %w[message system].freeze
  ROLES = %w[user assistant].freeze
  # The transcript is a window for watching the call, not its record (that is
  # the handoff card and the post-call transcript), and it is broadcast on
  # every turn, so only the latest entries are kept and long lines are cut.
  MAX_ENTRIES = 80
  MAX_TEXT_LENGTH = 2000
  MAX_CODE_LENGTH = 64
  TRANSFER_PHASES = %w[dialing connected failed].freeze
  MAX_DETAIL_LENGTH = 500
  MAX_SOURCE_LENGTH = 16

  pattr_initialize [:call!, :payload!]

  # nil when the payload has the documented shape, otherwise a message for the 422.
  def validation_error
    return 'live must be an object' unless payload.is_a?(Hash)

    seq_error || counters_error || transfer_failed_error || transcript_error || attention_error
  end

  # Returns true when the state was stored (and broadcast).
  def perform
    applied = call.with_lock do
      next false if call.terminal? || !newer?

      call.update!(live: live_state)
      true
    end
    return false unless applied

    Pathors::CallLifecycleService.new(call: call).live_updated
    broadcast
    applied
  end

  private

  def broadcast
    Rails.configuration.dispatcher.sync_dispatcher.dispatch(Events::Types::PATHORS_CALL_LIVE_UPDATED, Time.zone.now, call: call)
  end

  def newer?
    stored_seq = call.live&.dig('seq')
    stored_seq.nil? || payload[:seq] > stored_seq
  end

  def live_state
    {
      seq: payload[:seq],
      turns: payload[:turns],
      interruptions: payload[:interruptions],
      transfer_failed: payload[:transfer_failed],
      transcript: payload[:transcript].last(MAX_ENTRIES).map { |entry| stored_entry(entry) },
      attention: stored_attention,
      updated_at: Time.current.iso8601
    }.as_json
  end

  # Backends that predate `attention` send none; it is stored as nil then.
  def stored_attention
    attention = payload[:attention]
    return if attention.nil?

    request = attention[:takeover_request]
    transfer = attention[:transfer]
    {
      takeover_request: request && { reason: request[:reason], detail: request[:detail].truncate(MAX_DETAIL_LENGTH),
                                     source: request[:source], at: request[:at] },
      transfer: transfer && { phase: transfer[:phase], target_masked: transfer[:target_masked],
                              failure_reason: transfer[:failure_reason], at: transfer[:at] },
      human_left_at: attention[:human_left_at]
    }
  end

  def stored_entry(entry)
    if entry[:kind] == 'message'
      { kind: 'message', role: entry[:role], content: entry[:content].truncate(MAX_TEXT_LENGTH),
        interrupted: entry[:interrupted] == true, at: entry[:at] }
    else
      { kind: 'system', code: entry[:code], text: entry[:text].truncate(MAX_TEXT_LENGTH), at: entry[:at] }
    end
  end

  def seq_error
    'seq must be a positive integer' unless payload[:seq].is_a?(Integer) && payload[:seq].positive?
  end

  def counters_error
    return if [payload[:turns], payload[:interruptions]].all? { |value| non_negative_integer?(value) }

    'turns and interruptions must be non-negative integers'
  end

  def transfer_failed_error
    'transfer_failed must be a boolean' unless [true, false].include?(payload[:transfer_failed])
  end

  def transcript_error
    transcript = payload[:transcript]
    return 'transcript must be an array' unless transcript.is_a?(Array)
    return if transcript.all? { |entry| valid_entry?(entry) }

    'each transcript entry needs kind message (role user or assistant, string content, optional boolean interrupted) ' \
      "or kind system (string code of at most #{MAX_CODE_LENGTH} chars, string text), and an optional integer at"
  end

  def attention_error
    attention = payload[:attention]
    return if attention.nil?
    return 'attention must be an object' unless attention.is_a?(Hash)
    return takeover_request_message unless optional_hash?(attention[:takeover_request]) { |request| valid_takeover_request?(request) }
    return transfer_message unless optional_hash?(attention[:transfer]) { |transfer| valid_transfer?(transfer) }

    'attention.human_left_at must be a non-negative integer' unless attention[:human_left_at].nil? || non_negative_integer?(attention[:human_left_at])
  end

  def takeover_request_message
    "attention.takeover_request needs string reason of at most #{MAX_CODE_LENGTH} chars, string detail, " \
      "string source of at most #{MAX_SOURCE_LENGTH} chars and an integer at"
  end

  def transfer_message
    "attention.transfer needs phase #{TRANSFER_PHASES.join(', ')}, optional strings target_masked and failure_reason " \
      "of at most #{MAX_CODE_LENGTH} chars, and an integer at"
  end

  def optional_hash?(value)
    value.nil? || (value.is_a?(Hash) && yield(value))
  end

  def valid_takeover_request?(request)
    short_string?(request[:reason], MAX_CODE_LENGTH) && request[:detail].is_a?(String) &&
      short_string?(request[:source], MAX_SOURCE_LENGTH) && non_negative_integer?(request[:at])
  end

  def valid_transfer?(transfer)
    TRANSFER_PHASES.include?(transfer[:phase]) && non_negative_integer?(transfer[:at]) &&
      [transfer[:target_masked], transfer[:failure_reason]].all? { |value| value.nil? || short_string?(value, MAX_CODE_LENGTH) }
  end

  def short_string?(value, max_length)
    value.is_a?(String) && value.length <= max_length
  end

  def valid_entry?(entry)
    return false unless entry.is_a?(Hash) && KINDS.include?(entry[:kind])
    return false unless entry[:at].nil? || non_negative_integer?(entry[:at])

    entry[:kind] == 'message' ? valid_message?(entry) : valid_system?(entry)
  end

  def valid_message?(entry)
    ROLES.include?(entry[:role]) && entry[:content].is_a?(String) && [nil, true, false].include?(entry[:interrupted])
  end

  def valid_system?(entry)
    entry[:code].is_a?(String) && entry[:code].length <= MAX_CODE_LENGTH && entry[:text].is_a?(String)
  end

  def non_negative_integer?(value)
    value.is_a?(Integer) && value >= 0
  end
end
