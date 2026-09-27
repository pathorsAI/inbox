# Relays a dashboard agent's "end call" click to the Pathors backend, which
# tells the voice agent to terminate the session. Unlike leaving (which only
# drops the human out of the room and hands the caller back to the AI), this
# ends the call for everyone.
#
# Only the agent currently holding the call may hang it up — the backend
# answers anyone else with 409 `not_call_owner`, and a call that is already
# over with 404. See Pathors::VoiceRelay for signing and status mapping.
class Pathors::CallHangupService < Pathors::VoiceRelay
  private

  def action
    'hangup'
  end
end
