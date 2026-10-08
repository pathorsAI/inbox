# A Pathors call only ends when the backend's call.ended webhook arrives, and
# the backend does not retry it. A call whose webhook was lost stays live
# forever: pinned at the top of every conversation list with a take-over button
# for a room that no longer exists. No real call runs this long, so ending it
# here is the safety net.
class Pathors::ExpireStaleCallsJob < ApplicationJob
  queue_as :low

  MAX_CALL_DURATION = 2.hours
  END_REASON = 'stale'.freeze

  def perform
    Call.pathors.active.where(started_at: ...MAX_CALL_DURATION.ago).find_each(batch_size: 100) do |call|
      # When it really ended is unknown, so ended_at stays blank.
      call.update!(status: 'completed', end_reason: END_REASON)
      # Fires MESSAGE_UPDATED so every dashboard drops it from the live list.
      # rubocop:disable Rails/SkipsModelValidations
      call.message&.touch
      # rubocop:enable Rails/SkipsModelValidations
    end
  end
end
