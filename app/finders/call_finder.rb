class CallFinder
  RESULTS_PER_PAGE = 25

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
    filter_by_status
    filter_by_direction
    filter_by_inbox
    filter_by_agent

    { calls: paginated_calls, count: @calls.count }
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

  def paginated_calls
    @calls.includes(:contact, :conversation, :accepted_by_agent, inbox: :channel)
          .order(created_at: :desc)
          .page(@params[:page] || 1)
          .per(RESULTS_PER_PAGE)
  end
end
