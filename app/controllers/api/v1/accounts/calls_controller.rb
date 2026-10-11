class Api::V1::Accounts::CallsController < Api::V1::Accounts::BaseController
  ENUM_FILTERS = { segment: CallFinder::SEGMENTS, outcome: CallFinder::OUTCOME_FILTERS }.freeze
  EPOCH_FILTERS = %i[since until].freeze

  before_action :validate_filters, only: [:index]

  def index
    result = CallFinder.new(Current.user, Current.account, params).perform
    @calls = result[:calls]
    @calls_count = result[:count]
    @segment_counts = result[:counts]
    @handoff_variables = result[:handoff_variables]
  end

  def show
    result = CallFinder.new(Current.user, Current.account, params).find(params[:id])
    @call = result[:call]
    @handoff_variables = result[:handoff_variables]
  end

  private

  def validate_filters
    invalid = (ENUM_FILTERS.keys + EPOCH_FILTERS).find { |key| params[key].present? && !valid_filter?(key, params[key]) }
    render json: { error: "Invalid #{invalid}" }, status: :unprocessable_entity if invalid
  end

  def valid_filter?(key, value)
    return value.to_s.match?(/\A\d+\z/) if EPOCH_FILTERS.include?(key)

    ENUM_FILTERS.fetch(key).include?(value)
  end
end
