# Relays a dashboard agent's "join call" click to the Pathors backend, which
# owns the LiveKit room the voice agent is already speaking in and hands back a
# participant token so the human can drop into the same room.
#
# The backend arbitrates who wins the race (409) and whether the call is still
# alive (404); see Pathors::VoiceRelay for signing and status mapping.
class Pathors::CallJoinService < Pathors::VoiceRelay
  private

  def action
    'join'
  end
end
