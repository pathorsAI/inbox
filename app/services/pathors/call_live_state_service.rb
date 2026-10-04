# Stores what the Pathors voice agent is doing on a live call — turn and
# interruption counts, whether a transfer failed, and a window of the
# transcript — so agents can follow the call in the dashboard before anyone
# takes it over.
#
# The backend pushes the whole state on every turn, and deliveries can arrive
# out of order. `seq` (monotonic per call) decides which one wins: an update no
# newer than the stored one, or one for a call that already ended, is dropped.
# The row lock keeps two concurrent deliveries from both passing that check.
#
# Nothing here becomes a chat message; the caller rebroadcasts the call's
# voice_call message so the bubble and the conversation list pick it up.
class Pathors::CallLiveStateService
  KINDS = %w[message system].freeze
  ROLES = %w[user assistant].freeze
  # The transcript is a window for watching the call, not its record (that is
  # the handoff card and the post-call transcript), and it is broadcast on
  # every turn, so only the latest entries are kept and long lines are cut.
  MAX_ENTRIES = 80
  MAX_TEXT_LENGTH = 2000
  MAX_CODE_LENGTH = 64

  pattr_initialize [:call!, :payload!]

  # nil when the payload has the documented shape, otherwise a message for the 422.
  def validation_error
    return 'live must be an object' unless payload.is_a?(Hash)

    seq_error || counters_error || transfer_failed_error || transcript_error
  end

  # Returns true when the state was stored.
  def perform
    call.with_lock do
      next false if call.terminal? || !newer?

      call.update!(live: live_state)
      true
    end
  end

  private

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
      updated_at: Time.current.iso8601
    }.as_json
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
