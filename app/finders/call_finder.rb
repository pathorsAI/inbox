class CallFinder
  RESULTS_PER_PAGE = 25
  SEGMENTS = %w[need live ended].freeze
  # `takeover_requested` is not an outcome but filters alongside them: "calls
  # the AI asked help on", whatever came of it.
  OUTCOME_FILTERS = (Pathors::CallLifecycleService::OUTCOMES + %w[takeover_requested]).freeze
  # Fewer digits than this is a name, not a phone number fragment.
  MIN_PHONE_DIGITS = 3

  def initialize(current_user, current_account, params)
    @current_user = current_user
    @current_account = current_account
    @params = params
  end

  def perform
    # `calls` is not an account association; scope explicitly, the way
    # Api::V1::Accounts::Pathors::CallsController already does.
    @calls = Call.where(account_id: @current_account.id)
    filter_by_visibility
    filter_by_inbox
    # The segment badges count what the viewer could switch to, so they ignore
    # the segment, search and date filters below.
    counts = segment_counts

    filter_by_status
    filter_by_direction
    filter_by_agent
    filter_by_segment
    filter_by_query
    filter_by_date
    filter_by_outcome
    filter_by_mine

    calls = paginated_calls
    { calls: calls, count: @calls.count, counts: counts, handoff_variables: handoff_variables(calls) }
  end

  private

  # Administrators see the whole account; everyone else sees the calls that sit
  # in conversations they can open in the dashboard — the same bar the join
  # endpoint enforces with `authorize conversation, :show?`.
  def filter_by_visibility
    return if Current.account_user&.administrator?

    @calls = @calls.where(conversation_id: accessible_conversations)
  end

  def accessible_conversations
    Conversations::PermissionFilterService.new(@current_account.conversations, @current_user, @current_account).perform.select(:id)
  end

  def segment_counts
    { need: @calls.needing_action.count, live: @calls.active.count }
  end

  def filter_by_status
    @calls = @calls.where(status: Call.status_from_display(@params[:status])) if @params[:status].present?
  end

  def filter_by_direction
    @calls = @calls.where(direction: Call.direction_from_label(@params[:direction])) if @params[:direction].present?
  end

  def filter_by_inbox
    @calls = @calls.where(inbox_id: @params[:inbox_id]) if @params[:inbox_id].present?
  end

  def filter_by_agent
    @calls = @calls.where(accepted_by_agent_id: @params[:agent_id]) if @params[:agent_id].present?
  end

  def filter_by_segment
    case @params[:segment]
    when 'need' then @calls = @calls.needing_action
    when 'live' then @calls = @calls.active
    when 'ended' then @calls = @calls.ended
    end
  end

  # Digits search the caller's number; anything else the contact's name.
  def filter_by_query
    query = @params[:q].to_s.strip
    return if query.blank?

    digits = query.gsub(/\D/, '')
    @calls = @calls.left_outer_joins(:contact)
    @calls = digits.length >= MIN_PHONE_DIGITS ? matching_number(digits) : matching_name(query)
  end

  # Numbers are stored in E.164 (+886912345678) but typed nationally
  # (0912345678), so the trunk prefix is dropped; a partial number (5678)
  # matches anywhere in it.
  def matching_number(digits)
    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(digits.delete_prefix('0'))}%"
    @calls.where("contacts.phone_number LIKE :pattern OR calls.meta->>'from_number' LIKE :pattern", pattern: pattern)
  end

  def matching_name(query)
    @calls.where('contacts.name ILIKE :pattern', pattern: "%#{ActiveRecord::Base.sanitize_sql_like(query)}%")
  end

  # Epoch seconds; the dashboard computes the day boundaries in the viewer's
  # time zone. `until` is exclusive so consecutive days do not overlap.
  def filter_by_date
    @calls = @calls.where('COALESCE(calls.started_at, calls.created_at) >= ?', Time.zone.at(@params[:since].to_i)) if @params[:since].present?
    @calls = @calls.where('COALESCE(calls.started_at, calls.created_at) < ?', Time.zone.at(@params[:until].to_i)) if @params[:until].present?
  end

  def filter_by_outcome
    outcome = @params[:outcome]
    return if outcome.blank?

    @calls = if outcome == 'takeover_requested'
               @calls.where("calls.meta->>'takeover_requested' = 'true'")
             else
               @calls.where("calls.meta->>'outcome' = ?", outcome)
             end
  end

  # Calls this agent took over, whether they still hold the call or only the
  # conversation it left behind.
  def filter_by_mine
    return unless ActiveModel::Type::Boolean.new.cast(@params[:mine])

    assigned = @current_account.conversations.where(assignee_id: @current_user.id).select(:id)
    @calls = @calls.where(accepted_by_agent_id: @current_user.id).or(@calls.where(conversation_id: assigned))
  end

  def paginated_calls
    @calls.includes(:contact, :conversation, :accepted_by_agent, inbox: :channel)
          .order(@params[:segment] == 'live' ? { started_at: :asc } : { created_at: :desc })
          .page(@params[:page] || 1)
          .per(RESULTS_PER_PAGE)
  end

  # What the AI extracted lives on the call's handoff card, one message per
  # call; the page's cards are read in one query rather than one per row.
  def handoff_variables(calls)
    ids = calls.filter_map(&:handoff_message_id)
    return {} if ids.empty?

    Message.where(account_id: @current_account.id, id: ids).select(:id, :content_attributes)
           .to_h { |message| [message.id, message.content_attributes.dig('data', 'variables')] }
  end
end
