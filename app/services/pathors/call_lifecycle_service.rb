# The one home for what a Pathors call means for the people in the Inbox. The
# rule it keeps is "an open conversation needs a human":
#
#   AI handling the call             pending, assigned to the Pathors bot
#   AI asked for help / transfer     open, bot removed (CONVERSATION_BOT_HANDOFF
#   failed and nobody answered       notifies the inbox's agents)
#   a human joined                   open, assigned to the joiner
#   ended with that request unmet    stays open, call flagged follow_up (待回電)
#   ended, AI-only or transferred    resolved
#   ended after a human took over    left for the human to close
#
# The call side lives in `calls.meta` (see Call) and is read-modify-written
# under the call's row lock, because live updates, joins and the end webhook
# race each other. The conversation side is a best-effort follow-up: it runs
# after the lock, and a Chatwoot validation that refuses it (required
# attributes, a closed ticket) is logged rather than raised, because every
# entry point here answers a Pathors backend webhook that must not fail over it.
class Pathors::CallLifecycleService
  OUTCOMES = %w[no_answer transferred human transfer_failed hangup ai_done].freeze
  # Outcomes with no one left to talk to, so the conversation is closed for the
  # agents unless a human got involved.
  AUTO_RESOLVED_OUTCOMES = %w[ai_done transferred hangup no_answer].freeze
  TRANSFER_BLOCKING_PHASES = %w[dialing connected].freeze
  TRANSFER_FAILED_END_REASONS = %w[transfer_failed transfer_abandoned].freeze
  # Shorter than this with nothing else to say about it, the caller just hung up.
  HANGUP_MAX_SECONDS = 15

  pattr_initialize [:call!]

  # After every stored live update. Returns nothing; the caller broadcasts the
  # call, which by then carries the new needs_action.
  def live_updated
    handed_over, newly_requested, human_left = call.with_lock { apply_live_state }

    rebroadcast_bubble if human_left
    attributes = newly_requested ? { pathors_takeover_requested: true } : {}
    update_conversation(hand_over: handed_over, attributes: attributes) if handed_over || attributes.present?
  end

  def joined(user)
    call.with_lock do
      call.update!(accepted_by_agent_id: user.id, accepted_at: now_ms, needs_action: false, human_joined: true)
    end
    # So every other dashboard sees who answered and drops the attention alert.
    # The bubble's MESSAGE_UPDATED also reaches the contact, so needs_action
    # cannot ride on it; the agent-only live broadcast carries it.
    rebroadcast_bubble
    broadcast_live_state
    assign_conversation_to(user)
  end

  # "略過" mutes the attention alert for this agent only.
  def dismiss(user)
    call.with_lock do
      dismissed_by = Array(call.dismissed_by)
      call.update!(dismissed_by: dismissed_by + [user.id]) if dismissed_by.exclude?(user.id)
    end
  end

  def resolve_follow_up
    call.with_lock { call.update!(follow_up: false) if call.follow_up }
  end

  # When the call reaches a terminal status. Safe to repeat: a terminal to
  # terminal correction recomputes the outcome but never takes back a follow-up.
  def ended
    follow_up = call.with_lock { apply_end }

    attributes = { pathors_call_outcome: call.outcome }
    if follow_up
      update_conversation(hand_over: true, attributes: attributes)
    else
      update_conversation(resolve: auto_resolve?, attributes: attributes)
    end
  end

  private

  # Returns [handed_over, newly_requested, human_left].
  def apply_live_state
    human_left = release_departed_human
    was_needed = call.needs_action == true
    newly_requested = takeover_request.present? && call.takeover_requested != true

    call.takeover_requested = true if newly_requested
    call.needs_action = needs_action?
    call.save! if call.changed?

    [call.needs_action && !was_needed, newly_requested, human_left]
  end

  # The backend reports the human leaving; the AI has the call back, so the
  # bubble and the live list must stop naming that agent. `accepted_at` stays:
  # it is what marks a request or a failed transfer as already answered, and a
  # request the human dealt with must not come back once they hang up.
  def release_departed_human
    left_at = attention['human_left_at']
    return false if left_at.nil? || call.accepted_at.nil? || call.accepted_by_agent_id.nil?
    return false unless left_at > call.accepted_at

    call.accepted_by_agent_id = nil
    true
  end

  def needs_action?
    return false if call.terminal? || call.accepted_by_agent_id.present?
    return false if TRANSFER_BLOCKING_PHASES.include?(transfer&.dig('phase'))

    request_open? || failed_transfer_open?
  end

  def request_open?
    takeover_request.present? && unanswered_since?(takeover_request['at'])
  end

  # `transfer_failed` is what backends without `attention` send; it carries no
  # time, so any join answers it.
  def failed_transfer_open?
    return transfer['phase'] == 'failed' && unanswered_since?(transfer['at']) if transfer.present?

    call.live&.dig('transfer_failed') == true && call.accepted_at.nil?
  end

  def unanswered_since?(at)
    call.accepted_at.nil? || call.accepted_at < at
  end

  # Returns whether this end left a follow-up behind.
  def apply_end
    follow_up = call.needs_action == true && call.human_joined != true
    call.outcome = outcome
    call.follow_up = true if follow_up
    call.needs_action = false
    call.save! if call.changed?
    follow_up
  end

  # First match wins, in this order.
  def outcome
    return 'no_answer' if call.status == 'no_answer'
    return 'transferred' if transferred?
    return 'human' if human_handled?
    return 'transfer_failed' if transfer_failed?
    return 'hangup' if short_call?

    'ai_done'
  end

  def transferred?
    end_reason == 'transferred' || last_transfer_phase == 'connected'
  end

  def human_handled?
    call.human_joined == true || end_reason == 'human_takeover'
  end

  def transfer_failed?
    TRANSFER_FAILED_END_REASONS.include?(end_reason) || last_transfer_phase == 'failed'
  end

  # A call whose length is unknown (an expired one) is not assumed short.
  def short_call?
    call.duration_seconds.present? && call.duration_seconds < HANGUP_MAX_SECONDS
  end

  def last_transfer_phase
    transfer&.dig('phase')
  end

  # The backend's vocabulary is snake_case, but its camelCase spellings
  # (`userHangup`) have shipped too.
  def end_reason
    call.end_reason.to_s.underscore
  end

  def auto_resolve?
    call.human_joined != true && AUTO_RESOLVED_OUTCOMES.include?(call.outcome)
  end

  # A human answering an unassigned conversation claims it, the way picking up
  # a phone does; a bot-held one too — AssignmentService opens it and drops the
  # bot. An existing human assignee is never overwritten.
  def assign_conversation_to(user)
    conversation = call.conversation
    return if conversation.assignee_id.present?

    ::Conversations::AssignmentService.new(conversation: conversation, assignee_id: user.id).perform
  rescue StandardError => e
    report_conversation_failure(e)
  end

  # hand_over: give the conversation to humans (open, no bot) unless a human
  # already holds it. resolve: close a conversation only the AI ever handled.
  def update_conversation(attributes:, hand_over: false, resolve: false)
    conversation = call.conversation
    conversation.custom_attributes = conversation_attributes(conversation, attributes)

    if hand_over
      hand_to_humans(conversation)
    elsif resolve && conversation.pending? && conversation.assignee_id.blank?
      resolve_for_ai(conversation)
    elsif conversation.changed?
      conversation.save!
    end
  rescue StandardError => e
    report_conversation_failure(e)
  end

  def hand_to_humans(conversation)
    return conversation.save! if conversation.assignee_id.present?
    # bot_handoff! also saves the attributes set above, in the same update.
    return conversation.bot_handoff! if conversation.pending?

    conversation.ai_assignee = nil
    conversation.status = :open
    conversation.save! if conversation.changed?
  end

  # A resolve the account's rules refuse (required attributes) leaves the
  # conversation where it was; the outcome attribute is still recorded.
  def resolve_for_ai(conversation)
    conversation.status = :resolved
    return if conversation.save

    Rails.logger.warn("Pathors call #{call.id}: conversation #{conversation.id} not resolved: #{conversation.errors.full_messages.to_sentence}")
    conversation.restore_attributes(%w[status])
    conversation.save! if conversation.changed?
  end

  # `pathors_call_from` rides along so the other party's number is filterable
  # in the conversation list, which has no column for it. On an outbound call
  # `from_number` is our own line, so the dialled number is the one kept.
  def conversation_attributes(conversation, attributes)
    extra = { pathors_call_from: (call.incoming? ? call.from_number : call.to_number).presence }.compact
    conversation.custom_attributes.to_h.merge(extra.merge(attributes).stringify_keys)
  end

  def report_conversation_failure(error)
    Rails.logger.error("Pathors call #{call.id}: conversation update failed: #{error.class}: #{error.message}")
    ChatwootExceptionTracker.new(error, account: call.account).capture_exception
  end

  # Fires MESSAGE_UPDATED, whose payload embeds the call, so every dashboard
  # re-renders the bubble with the new handler.
  def rebroadcast_bubble
    # rubocop:disable Rails/SkipsModelValidations
    call.message&.touch
    # rubocop:enable Rails/SkipsModelValidations
  end

  def broadcast_live_state
    Rails.configuration.dispatcher.sync_dispatcher.dispatch(Events::Types::PATHORS_CALL_LIVE_UPDATED, Time.zone.now, call: call)
  end

  def attention
    call.live&.dig('attention') || {}
  end

  def takeover_request
    attention['takeover_request']
  end

  def transfer
    attention['transfer']
  end

  def now_ms
    (Time.current.to_f * 1000).to_i
  end
end
