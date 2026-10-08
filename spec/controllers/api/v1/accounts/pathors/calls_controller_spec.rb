require 'rails_helper'

RSpec.describe 'Pathors Calls API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:conversation) { create(:conversation, account: account) }

  let(:create_payload) do
    {
      conversation_id: conversation.display_id,
      provider_call_id: 'pathors-call-1',
      direction: 'inbound',
      from_number: '+886912345678',
      to_number: '+886222222222',
      started_at: '2026-08-05T10:00:00Z'
    }
  end

  describe 'POST /api/v1/accounts/{account.id}/pathors/calls' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/pathors/calls", params: create_payload, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an agent' do
      it 'creates the call' do
        post "/api/v1/accounts/#{account.id}/pathors/calls",
             params: create_payload, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(Call.last.provider).to eq('pathors')
      end
    end

    context 'when it is an agent bot' do
      it 'creates the call' do
        post "/api/v1/accounts/#{account.id}/pathors/calls",
             params: create_payload, headers: { api_access_token: agent_bot.access_token.token }, as: :json

        expect(response).to have_http_status(:success)
        expect(Call.last.provider).to eq('pathors')
      end
    end

    context 'when it is an administrator' do
      it 'creates a pathors call and a voice_call message' do
        expect do
          post "/api/v1/accounts/#{account.id}/pathors/calls",
               params: create_payload, headers: admin.create_new_auth_token, as: :json
        end.to change(Call, :count).by(1)

        expect(response).to have_http_status(:success)

        call = Call.last
        expect(call.provider).to eq('pathors')
        expect(call.direction).to eq('incoming')
        expect(call.status).to eq('in_progress')
        expect(call.from_number).to eq('+886912345678')
        expect(call.message).to be_present
      end

      it 'creates an incoming voice_call message for an inbound call' do
        post "/api/v1/accounts/#{account.id}/pathors/calls",
             params: create_payload, headers: admin.create_new_auth_token, as: :json

        message = Call.last.message
        expect(message.content_type).to eq('voice_call')
        expect(message.message_type).to eq('incoming')
        expect(message.conversation_id).to eq(conversation.id)
      end

      it 'creates a call on a conversation that belongs to a voice inbox' do
        voice_inbox = create(:channel_voice, account: account, phone_number: '+886222222222').inbox
        contact_inbox = ContactInboxWithContactBuilder.new(
          inbox: voice_inbox,
          contact_attributes: { phone_number: '+886912345678' }
        ).perform
        voice_conversation = create(:conversation, account: account, inbox: voice_inbox, contact_inbox: contact_inbox,
                                                   contact: contact_inbox.contact)

        post "/api/v1/accounts/#{account.id}/pathors/calls",
             params: create_payload.merge(conversation_id: voice_conversation.display_id),
             headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        call = Call.last
        expect(call.inbox_id).to eq(voice_inbox.id)
        expect(call.message.conversation_id).to eq(voice_conversation.id)
      end

      it 'creates an outgoing voice_call message for an outbound call' do
        post "/api/v1/accounts/#{account.id}/pathors/calls",
             params: create_payload.merge(direction: 'outbound'),
             headers: admin.create_new_auth_token, as: :json

        call = Call.last
        expect(call.direction).to eq('outgoing')
        expect(call.message.message_type).to eq('outgoing')
      end

      it 'responds with the push event payload plus the message id' do
        post "/api/v1/accounts/#{account.id}/pathors/calls",
             params: create_payload, headers: admin.create_new_auth_token, as: :json

        call = Call.last
        body = response.parsed_body
        expect(body['id']).to eq(call.id)
        expect(body['status']).to eq('in-progress')
        expect(body['direction']).to eq('incoming')
        expect(body['accepted_by_agent_name']).to eq('Pathors AI')
        expect(body['message_id']).to eq(call.message_id)
      end

      it 'is idempotent for a repeated provider_call_id' do
        post "/api/v1/accounts/#{account.id}/pathors/calls",
             params: create_payload, headers: admin.create_new_auth_token, as: :json
        first_id = response.parsed_body['id']

        expect do
          post "/api/v1/accounts/#{account.id}/pathors/calls",
               params: create_payload, headers: admin.create_new_auth_token, as: :json
        end.not_to change(Call, :count)

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['id']).to eq(first_id)
      end

      it 'rejects an unknown direction' do
        post "/api/v1/accounts/#{account.id}/pathors/calls",
             params: create_payload.merge(direction: 'sideways'),
             headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'returns not found for a conversation outside the account' do
        post "/api/v1/accounts/#{account.id}/pathors/calls",
             params: create_payload.merge(conversation_id: conversation.display_id + 9999),
             headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/pathors/calls/{id}' do
    let(:message) do
      create(:message, account: account, conversation: conversation, inbox: conversation.inbox, content_type: 'voice_call')
    end
    let(:call) do
      create(:call, :pathors, account: account, conversation: conversation, inbox: conversation.inbox,
                              contact: conversation.contact, message: message)
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        patch "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}", params: { status: 'completed' }, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an agent' do
      it 'updates the call' do
        patch "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}",
              params: { status: 'completed' }, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(call.reload.status).to eq('completed')
      end
    end

    context 'when it is an agent bot' do
      it 'updates the call' do
        patch "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}",
              params: { status: 'completed' }, headers: { api_access_token: agent_bot.access_token.token }, as: :json

        expect(response).to have_http_status(:success)
        expect(call.reload.status).to eq('completed')
      end
    end

    context 'when it is an administrator' do
      it 'updates the status, duration and end reason' do
        patch "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}",
              params: { status: 'completed', duration_seconds: 42, end_reason: 'hangup', ended_at: '2026-08-05T10:05:00Z' },
              headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        call.reload
        expect(call.status).to eq('completed')
        expect(call.duration_seconds).to eq(42)
        expect(call.end_reason).to eq('hangup')
        expect(call.ended_at).to eq(Time.zone.parse('2026-08-05T10:05:00Z').iso8601)
      end

      it 'touches the linked message so the dashboard re-renders' do
        original = message.updated_at

        travel_to(2.minutes.from_now) do
          patch "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}",
                params: { status: 'completed' }, headers: admin.create_new_auth_token, as: :json
        end

        expect(message.reload.updated_at).to be > original
      end

      it 'responds with the display status' do
        patch "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}",
              params: { status: 'no_answer' }, headers: admin.create_new_auth_token, as: :json

        expect(response.parsed_body['status']).to eq('no-answer')
      end

      it 'accepts the dashed display status on the way in' do
        patch "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}",
              params: { status: 'in-progress' }, headers: admin.create_new_auth_token, as: :json

        expect(call.reload.status).to eq('in_progress')
      end

      it 'ignores a transition out of a terminal status' do
        call.update!(status: 'completed')

        patch "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}",
              params: { status: 'in_progress', duration_seconds: 99 }, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        call.reload
        expect(call.status).to eq('completed')
        expect(call.duration_seconds).to be_nil
        expect(response.parsed_body['status']).to eq('completed')
      end

      it 'stores the recording_url alongside the terminal status' do
        patch "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}",
              params: { status: 'completed', recording_url: 'https://cdn.pathors.example/recordings/abc.mp3' },
              headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(call.reload.recording_url).to eq('https://cdn.pathors.example/recordings/abc.mp3')
        expect(response.parsed_body['recording_url']).to eq('https://cdn.pathors.example/recordings/abc.mp3')
      end

      it 'accepts a late recording_url written back after the call completed' do
        call.update!(status: 'completed')

        patch "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}",
              params: { recording_url: 'https://cdn.pathors.example/recordings/abc.mp3' },
              headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(call.reload.recording_url).to eq('https://cdn.pathors.example/recordings/abc.mp3')
      end

      it 'accepts a late transcript written back after the call completed' do
        call.update!(status: 'completed')

        patch "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}",
              params: { transcript: 'Agent: hello. Caller: hi.' },
              headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(call.reload.transcript).to eq('Agent: hello. Caller: hi.')
        expect(response.parsed_body['transcript']).to eq('Agent: hello. Caller: hi.')
      end

      it 'keeps the recording_url from a webhook whose status would regress' do
        call.update!(status: 'completed')

        patch "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}",
              params: { status: 'in_progress', duration_seconds: 99, recording_url: 'https://cdn.pathors.example/recordings/abc.mp3' },
              headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        call.reload
        expect(call.recording_url).to eq('https://cdn.pathors.example/recordings/abc.mp3')
        expect(call.status).to eq('completed')
        expect(call.duration_seconds).to be_nil
      end

      it 'rejects a recording_url that is not http(s)' do
        patch "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}",
              params: { status: 'completed', recording_url: 'javascript:alert(1)' },
              headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        call.reload
        expect(call.recording_url).to be_nil
        expect(call.status).not_to eq('completed')
      end

      it 'rejects an unparseable recording_url' do
        patch "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}",
              params: { recording_url: 'http://exa mple.com/a.mp3' },
              headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(call.reload.recording_url).to be_nil
      end

      it 'allows a terminal to terminal correction' do
        call.update!(status: 'completed')

        patch "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}",
              params: { status: 'failed' }, headers: admin.create_new_auth_token, as: :json

        expect(call.reload.status).to eq('failed')
      end

      it 'returns not found for a call outside the account' do
        other_call = create(:call, :pathors)

        patch "/api/v1/accounts/#{account.id}/pathors/calls/#{other_call.id}",
              params: { status: 'completed' }, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/pathors/calls/{id}/join' do
    let(:join_url) { 'https://api.pathors.example/project/proj_42/integration/chatwoot/voice/join' }
    let(:message) do
      create(:message, account: account, conversation: conversation, inbox: conversation.inbox, content_type: 'voice_call')
    end
    let(:call) do
      create(:call, :pathors, account: account, conversation: conversation, inbox: conversation.inbox,
                              contact: conversation.contact, message: message, status: 'ringing')
    end
    let!(:agent_bot) do
      create(:agent_bot, account: account,
                         outgoing_url: 'https://api.pathors.example/project/proj_42/integration/chatwoot/callback')
    end
    let(:join_response) do
      {
        token: 'lk-token', serverUrl: 'wss://livekit.example', roomName: 'room-1',
        participantIdentity: "chatwoot-human-#{agent.id}", yieldDelivered: true
      }
    end

    # Fixtures first: the factories draw from SecureRandom.uuid too.
    def stub_request_id
      call
      allow(SecureRandom).to receive(:uuid).and_return('req-1')
    end

    def stub_join(status: 200, body: nil)
      stub_request(:post, join_url).to_return(
        status: status,
        body: (body || join_response).to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
    end

    before do
      create(:inbox_member, user: agent, inbox: conversation.inbox)
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}/join", as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the agent has no access to the conversation' do
      let(:outsider) { create(:user, account: account, role: :agent) }

      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}/join",
             headers: outsider.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an agent with conversation access' do
      it 'relays the pathors join payload' do
        stub_join

        post "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}/join",
             headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['token']).to eq('lk-token')
        expect(response.parsed_body['serverUrl']).to eq('wss://livekit.example')
      end

      it 'signs the timestamp and exact raw request body with the agent bot secret' do
        stub_join
        stub_request_id

        freeze_time do
          post "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}/join",
               headers: agent.create_new_auth_token, as: :json

          expected_body = {
            action: 'join',
            sessionId: call.provider_call_id,
            conversationId: conversation.display_id,
            agent: { id: agent.id, name: agent.available_name },
            requestId: 'req-1'
          }.to_json
          timestamp = Time.current.to_i.to_s
          expected_signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', agent_bot.secret, "#{timestamp}.#{expected_body}")}"

          expect(
            a_request(:post, join_url).with(
              body: expected_body,
              headers: { 'X-Pathors-Timestamp' => timestamp, 'X-Pathors-Signature' => expected_signature }
            )
          ).to have_been_made.once
        end
      end

      it 'records the answering agent and touches the message' do
        stub_join
        original = message.updated_at

        travel_to(2.minutes.from_now) do
          post "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}/join",
               headers: agent.create_new_auth_token, as: :json
        end

        expect(call.reload.accepted_by_agent_id).to eq(agent.id)
        expect(message.reload.updated_at).to be > original
      end

      it 'assigns the conversation to the joining agent when unassigned' do
        stub_join

        post "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}/join",
             headers: agent.create_new_auth_token, as: :json

        expect(conversation.reload.assignee_id).to eq(agent.id)
      end

      it 'leaves an existing assignee untouched' do
        other_agent = create(:user, account: account, role: :agent)
        create(:inbox_member, user: other_agent, inbox: conversation.inbox)
        conversation.update!(assignee: other_agent)
        stub_join

        post "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}/join",
             headers: agent.create_new_auth_token, as: :json

        expect(conversation.reload.assignee_id).to eq(other_agent.id)
      end

      it 'relays a 409 already_claimed verbatim' do
        stub_join(status: 409, body: { error: 'already_claimed' })

        post "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}/join",
             headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:conflict)
        expect(response.parsed_body['error']).to eq('already_claimed')
        expect(call.reload.accepted_by_agent_id).to be_nil
      end

      it 'relays a 404 call_not_found verbatim' do
        stub_join(status: 404, body: { error: 'call_not_found' })

        post "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}/join",
             headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body['error']).to eq('call_not_found')
      end

      it 'reports a rejected signature as a server error' do
        stub_join(status: 401, body: { error: 'invalid_signature' })

        post "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}/join",
             headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:bad_gateway)
        expect(response.parsed_body['error']).to eq('pathors_auth_failed')
      end

      it 'reports an unreachable backend as a bad gateway' do
        stub_request(:post, join_url).to_timeout

        post "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}/join",
             headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:bad_gateway)
        expect(response.parsed_body['error']).to eq('pathors_unreachable')
      end

      it 'returns gone for a terminal call without contacting pathors' do
        stub_join
        call.update!(status: 'completed')

        post "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}/join",
             headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:gone)
        expect(response.parsed_body['error']).to eq('call_ended')
        expect(a_request(:post, join_url)).not_to have_been_made
      end

      it 'returns not found for a non-pathors call without contacting pathors' do
        stub_join
        twilio_call = create(:call, account: account, conversation: conversation, inbox: conversation.inbox,
                                    contact: conversation.contact)

        post "/api/v1/accounts/#{account.id}/pathors/calls/#{twilio_call.id}/join",
             headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
        expect(a_request(:post, join_url)).not_to have_been_made
      end

      it 'returns unprocessable entity when no pathors agent bot is configured' do
        agent_bot.update!(outgoing_url: 'https://example.com/other')

        post "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}/join",
             headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('pathors_not_configured')
      end

      context 'when the account holds bots for more than one pathors project' do
        let(:inbox_join_url) { 'https://api.pathors.example/project/proj_99/integration/chatwoot/voice/join' }
        let(:inbox_bot) do
          create(:agent_bot, account: account,
                             outgoing_url: 'https://api.pathors.example/project/proj_99/integration/chatwoot/callback')
        end

        before do
          stub_request(:post, inbox_join_url).to_return(
            status: 200, body: join_response.to_json, headers: { 'Content-Type' => 'application/json' }
          )
          stub_join
        end

        it 'signs with the bot bound to the call inbox rather than another project bot' do
          create(:agent_bot_inbox, inbox: conversation.inbox, agent_bot: inbox_bot)
          stub_request_id

          timestamp = nil
          freeze_time do
            timestamp = Time.current.to_i
            post "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}/join",
                 headers: agent.create_new_auth_token, as: :json
          end

          expected_body = {
            action: 'join',
            sessionId: call.provider_call_id,
            conversationId: conversation.display_id,
            agent: { id: agent.id, name: agent.available_name },
            requestId: 'req-1'
          }.to_json
          signed_payload = "#{timestamp}.#{expected_body}"
          expected_signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', inbox_bot.secret, signed_payload)}"

          expect(response).to have_http_status(:success)
          expect(
            a_request(:post, inbox_join_url).with(body: expected_body, headers: { 'X-Pathors-Signature' => expected_signature })
          ).to have_been_made.once
          expect(a_request(:post, join_url)).not_to have_been_made
        end

        it 'falls back to the account bot when the inbox has no bot bound' do
          inbox_bot

          post "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}/join",
               headers: agent.create_new_auth_token, as: :json

          expect(response).to have_http_status(:success)
          expect(a_request(:post, join_url)).to have_been_made.once
          expect(a_request(:post, inbox_join_url)).not_to have_been_made
        end

        it 'falls back to the account bot when the inbox is bound to a non-pathors bot' do
          other_bot = create(:agent_bot, account: account, outgoing_url: 'https://example.com/hooks/other')
          create(:agent_bot_inbox, inbox: conversation.inbox, agent_bot: other_bot)

          post "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}/join",
               headers: agent.create_new_auth_token, as: :json

          expect(response).to have_http_status(:success)
          expect(a_request(:post, join_url)).to have_been_made.once
        end
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/pathors/calls/{id}/hangup' do
    let(:hangup_url) { 'https://api.pathors.example/project/proj_42/integration/chatwoot/voice/hangup' }
    let(:message) do
      create(:message, account: account, conversation: conversation, inbox: conversation.inbox, content_type: 'voice_call')
    end
    let(:call) do
      create(:call, :pathors, account: account, conversation: conversation, inbox: conversation.inbox,
                              contact: conversation.contact, message: message, accepted_by_agent_id: agent.id)
    end
    let!(:agent_bot) do
      create(:agent_bot, account: account,
                         outgoing_url: 'https://api.pathors.example/project/proj_42/integration/chatwoot/callback')
    end

    # Fixtures first: the factories draw from SecureRandom.uuid too.
    def stub_request_id
      call
      allow(SecureRandom).to receive(:uuid).and_return('req-1')
    end

    def stub_hangup(status: 200, body: { ok: true })
      stub_request(:post, hangup_url).to_return(
        status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' }
      )
    end

    before do
      create(:inbox_member, user: agent, inbox: conversation.inbox)
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized without contacting pathors' do
        stub_hangup

        post "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}/hangup", as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(a_request(:post, hangup_url)).not_to have_been_made
      end
    end

    context 'when the agent has no access to the conversation' do
      let(:outsider) { create(:user, account: account, role: :agent) }

      it 'returns unauthorized without contacting pathors' do
        stub_hangup

        post "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}/hangup",
             headers: outsider.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(a_request(:post, hangup_url)).not_to have_been_made
      end
    end

    context 'when it is an agent with conversation access' do
      it 'relays the hangup with a timestamped signature' do
        stub_hangup
        stub_request_id

        freeze_time do
          post "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}/hangup",
               headers: agent.create_new_auth_token, as: :json

          expected_body = {
            action: 'hangup',
            sessionId: call.provider_call_id,
            conversationId: conversation.display_id,
            agent: { id: agent.id, name: agent.available_name },
            requestId: 'req-1'
          }.to_json
          timestamp = Time.current.to_i.to_s
          expected_signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', agent_bot.secret, "#{timestamp}.#{expected_body}")}"

          expect(response).to have_http_status(:success)
          expect(response.parsed_body['ok']).to be(true)
          expect(
            a_request(:post, hangup_url).with(
              body: expected_body,
              headers: { 'X-Pathors-Timestamp' => timestamp, 'X-Pathors-Signature' => expected_signature }
            )
          ).to have_been_made.once
        end
      end

      it 'leaves the call record and assignment untouched' do
        stub_hangup

        post "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}/hangup",
             headers: agent.create_new_auth_token, as: :json

        # The terminal status arrives through the update webhook once the voice
        # agent has actually torn the room down.
        expect(call.reload.status).to eq('in_progress')
        expect(conversation.reload.assignee_id).to be_nil
      end

      it 'relays a 409 not_call_owner verbatim' do
        stub_hangup(status: 409, body: { error: 'not_call_owner' })

        post "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}/hangup",
             headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:conflict)
        expect(response.parsed_body['error']).to eq('not_call_owner')
      end

      it 'relays a 404 call_not_found verbatim' do
        stub_hangup(status: 404, body: { error: 'call_not_found' })

        post "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}/hangup",
             headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body['error']).to eq('call_not_found')
      end

      it 'reports a rejected signature as a server error' do
        stub_hangup(status: 401, body: { error: 'unauthorized' })

        post "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}/hangup",
             headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:bad_gateway)
        expect(response.parsed_body['error']).to eq('pathors_auth_failed')
      end

      it 'reports a failed termination as a bad gateway' do
        stub_hangup(status: 500, body: { error: 'terminate_failed' })

        post "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}/hangup",
             headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:bad_gateway)
        expect(response.parsed_body['error']).to eq('pathors_error')
      end

      it 'returns gone for a terminal call without contacting pathors' do
        stub_hangup
        call.update!(status: 'completed')

        post "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}/hangup",
             headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:gone)
        expect(response.parsed_body['error']).to eq('call_ended')
        expect(a_request(:post, hangup_url)).not_to have_been_made
      end

      it 'returns not found for a non-pathors call without contacting pathors' do
        stub_hangup
        twilio_call = create(:call, account: account, conversation: conversation, inbox: conversation.inbox,
                                    contact: conversation.contact)

        post "/api/v1/accounts/#{account.id}/pathors/calls/#{twilio_call.id}/hangup",
             headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
        expect(a_request(:post, hangup_url)).not_to have_been_made
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/pathors/calls/{id}/handoff' do
    let(:call) do
      create(:call, :pathors, account: account, conversation: conversation, inbox: conversation.inbox,
                              contact: conversation.contact)
    end
    let(:handoff_url) { "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}/handoff" }
    let(:handoff_payload) do
      {
        transcript: [
          { role: 'assistant', content: 'How can I help?', timestamp: '2026-09-28T06:29:00Z' },
          { role: 'user', content: 'I want to change my booking.' }
        ],
        variables: { customer_name: 'Chen', booking_id: 'HS-240918', extra_bed: true, callback_phone: nil },
        transferred_at: '2026-09-28T06:32:00Z',
        ai_duration_seconds: 192
      }
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post handoff_url, params: handoff_payload, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an agent' do
      it 'returns unauthorized without posting a card' do
        expect do
          post handoff_url, params: handoff_payload, headers: agent.create_new_auth_token, as: :json
        end.not_to change(Message, :count)

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an administrator' do
      it 'posts the handoff card as an activity message' do
        expect do
          post handoff_url, params: handoff_payload, headers: admin.create_new_auth_token, as: :json
        end.to change(conversation.messages, :count).by(1)

        expect(response).to have_http_status(:created)
        message = conversation.messages.last
        expect(response.parsed_body['id']).to eq(message.id)
        expect(message.message_type).to eq('activity')
        expect(message.content_type).to eq('pathors_handoff')
        expect(message.sender).to be_nil
        expect(message.content_attributes['data']).to eq(
          'transcript' => [
            { 'role' => 'assistant', 'content' => 'How can I help?', 'timestamp' => '2026-09-28T06:29:00Z' },
            { 'role' => 'user', 'content' => 'I want to change my booking.' }
          ],
          'variables' => { 'customer_name' => 'Chen', 'booking_id' => 'HS-240918', 'extra_bed' => true, 'callback_phone' => nil },
          'transferred_at' => '2026-09-28T06:32:00Z',
          'ai_duration_seconds' => 192
        )
      end

      it 'renders a plain-text fallback and links the card to the call' do
        post handoff_url, params: handoff_payload, headers: admin.create_new_auth_token, as: :json

        message = conversation.messages.last
        expect(message.content).to eq(
          "AI handoff summary\n\ncustomer_name: Chen\nbooking_id: HS-240918\nextra_bed: true\ncallback_phone: Not captured\n\n" \
          "AI: How can I help?\nCaller: I want to change my booking."
        )
        expect(call.reload.handoff_message_id).to eq(message.id)
      end

      it 'returns the existing card on a repeated request instead of posting another' do
        post handoff_url, params: handoff_payload, headers: admin.create_new_auth_token, as: :json
        first_id = response.parsed_body['id']

        expect do
          post handoff_url, params: handoff_payload, headers: admin.create_new_auth_token, as: :json
        end.not_to change(Message, :count)

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['id']).to eq(first_id)
      end

      it 'accepts an empty transcript and empty variables' do
        post handoff_url, params: handoff_payload.merge(transcript: [], variables: {}, ai_duration_seconds: nil),
                          headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:created)
        expect(conversation.messages.last.content).to eq('AI handoff summary')
      end

      it 'rejects an unknown transcript role' do
        post handoff_url, params: handoff_payload.merge(transcript: [{ role: 'system', content: 'hi' }]),
                          headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'rejects a missing transferred_at' do
        post handoff_url, params: handoff_payload.except(:transferred_at), headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'rejects a transcript that is not an array' do
        post handoff_url, params: handoff_payload.merge(transcript: 'AI: hi'), headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(Message.where(content_type: 'pathors_handoff')).to be_empty
      end

      it 'rejects a variable value over the size cap' do
        oversized = { notes: 'x' * Pathors::CallHandoffService::MAX_VARIABLE_VALUE_LENGTH }

        post handoff_url, params: handoff_payload.merge(variables: oversized), headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(Message.where(content_type: 'pathors_handoff')).to be_empty
      end

      it 'returns not found for a call from another provider' do
        twilio_call = create(:call, account: account, conversation: conversation, inbox: conversation.inbox,
                                    contact: conversation.contact)

        post "/api/v1/accounts/#{account.id}/pathors/calls/#{twilio_call.id}/handoff",
             params: handoff_payload, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
      end

      it 'returns not found for a call in another account' do
        other_account = create(:account)
        other_conversation = create(:conversation, account: other_account)
        other_call = create(:call, :pathors, account: other_account, conversation: other_conversation,
                                             inbox: other_conversation.inbox, contact: other_conversation.contact)

        post "/api/v1/accounts/#{account.id}/pathors/calls/#{other_call.id}/handoff",
             params: handoff_payload, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'PUT /api/v1/accounts/{account.id}/pathors/calls/{id}/live' do
    let(:message) do
      create(:message, account: account, conversation: conversation, inbox: conversation.inbox, content_type: 'voice_call')
    end
    let(:call) do
      create(:call, :pathors, account: account, conversation: conversation, inbox: conversation.inbox,
                              contact: conversation.contact, message: message)
    end
    let(:live_url) { "/api/v1/accounts/#{account.id}/pathors/calls/#{call.id}/live" }
    let(:transcript) do
      [
        { kind: 'message', role: 'user', content: 'I want to book a room', at: 1_759_581_200_000 },
        { kind: 'message', role: 'assistant', content: 'For which night', interrupted: true, at: 1_759_581_201_000 },
        { kind: 'system', code: 'transfer_failed', text: 'Transfer failed: line busy', at: 1_759_581_202_000 }
      ]
    end
    let(:live_payload) do
      { live: { seq: 1_759_581_234_567, turns: 14, interruptions: 2, transfer_failed: true, transcript: transcript } }
    end

    def put_live(payload = live_payload, headers: admin.create_new_auth_token)
      put live_url, params: payload, headers: headers, as: :json
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        put live_url, params: live_payload, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an agent' do
      it 'returns unauthorized without storing anything' do
        create(:inbox_member, user: agent, inbox: conversation.inbox)

        put_live(headers: agent.create_new_auth_token)

        expect(response).to have_http_status(:unauthorized)
        expect(call.reload.live).to be_nil
      end
    end

    context 'when it is an agent bot' do
      it 'returns unauthorized' do
        put_live(headers: { api_access_token: agent_bot.access_token.token })

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an administrator' do
      it 'stores the live state on the call' do
        freeze_time do
          put_live

          expect(response).to have_http_status(:ok)
          expect(response.parsed_body).to eq('applied' => true)
          expect(call.reload.live).to eq(
            'seq' => 1_759_581_234_567, 'turns' => 14, 'interruptions' => 2, 'transfer_failed' => true,
            'transcript' => [
              { 'kind' => 'message', 'role' => 'user', 'content' => 'I want to book a room', 'interrupted' => false,
                'at' => 1_759_581_200_000 },
              { 'kind' => 'message', 'role' => 'assistant', 'content' => 'For which night', 'interrupted' => true,
                'at' => 1_759_581_201_000 },
              { 'kind' => 'system', 'code' => 'transfer_failed', 'text' => 'Transfer failed: line busy',
                'at' => 1_759_581_202_000 }
            ],
            'updated_at' => Time.current.iso8601
          )
        end
      end

      it 'broadcasts the state to inbox agents and administrators, never the contact' do
        create(:inbox_member, user: agent, inbox: conversation.inbox)
        call
        allow(ActionCableBroadcastJob).to receive(:perform_later)

        put_live

        expect(ActionCableBroadcastJob).to have_received(:perform_later).once.with(
          a_collection_containing_exactly(agent.pubsub_token, admin.pubsub_token),
          'pathors_call.live_updated',
          hash_including(id: call.id, conversation_id: conversation.display_id, inbox_id: conversation.inbox_id,
                         live: hash_including('seq' => 1_759_581_234_567, 'transcript' => a_collection_including(
                           hash_including('content' => 'I want to book a room')
                         )))
        )
        expect(ActionCableBroadcastJob).not_to have_received(:perform_later)
          .with(array_including(conversation.contact_inbox.pubsub_token), any_args)
      end

      it 'does not touch the message, so no message event, webhook or agent bot event fires' do
        call
        admin
        original = message.reload.updated_at

        travel_to(2.minutes.from_now) do
          expect { put_live }.not_to have_enqueued_job(EventDispatcherJob)
        end

        expect(message.reload.updated_at).to eq(original)
        expect(WebhookJob).not_to have_been_enqueued
        expect(AgentBots::WebhookJob).not_to have_been_enqueued
      end

      it 'does not write chat messages for transcript lines' do
        call

        expect { put_live }.not_to change(Message, :count)
      end

      it 'applies a newer seq over an older one' do
        put_live
        put_live({ live: live_payload[:live].merge(seq: 1_759_581_240_000, turns: 15) })

        expect(response.parsed_body).to eq('applied' => true)
        expect(call.reload.live['turns']).to eq(15)
      end

      it 'ignores a stale or repeated seq without broadcasting it' do
        put_live
        allow(ActionCableBroadcastJob).to receive(:perform_later)

        put_live({ live: live_payload[:live].merge(seq: 1_759_581_200_000, turns: 3) })
        expect(response.parsed_body).to eq('applied' => false)
        put_live({ live: live_payload[:live].merge(turns: 3) })
        expect(response.parsed_body).to eq('applied' => false)

        expect(response).to have_http_status(:ok)
        expect(call.reload.live['turns']).to eq(14)
        expect(ActionCableBroadcastJob).not_to have_received(:perform_later)
      end

      it 'ignores updates for a call that has ended' do
        call.update!(status: 'completed')

        put_live

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq('applied' => false)
        expect(call.reload.live).to be_nil
      end

      it 'keeps only the latest transcript entries and cuts long lines' do
        long_transcript = Array.new(Pathors::CallLiveStateService::MAX_ENTRIES + 5) do |index|
          { kind: 'message', role: 'user', content: "line #{index}", at: index }
        end
        long_transcript[-1] = { kind: 'message', role: 'assistant', content: 'x' * 3000, at: 99 }

        put_live({ live: live_payload[:live].merge(transcript: long_transcript) })

        stored = call.reload.live['transcript']
        expect(stored.size).to eq(Pathors::CallLiveStateService::MAX_ENTRIES)
        expect(stored.first['content']).to eq('line 5')
        expect(stored.last['content'].length).to eq(Pathors::CallLiveStateService::MAX_TEXT_LENGTH)
      end

      it 'drops keys outside the documented entry shape' do
        put_live({ live: live_payload[:live].merge(transcript: [{ kind: 'message', role: 'user', content: 'hi', extra: 'x' }]) })

        expect(call.reload.live['transcript']).to eq([{ 'kind' => 'message', 'role' => 'user', 'content' => 'hi',
                                                        'interrupted' => false, 'at' => nil }])
      end

      it 'rejects an unknown entry kind' do
        put_live({ live: live_payload[:live].merge(transcript: [{ kind: 'tool', content: 'lookup' }]) })

        expect(response).to have_http_status(:unprocessable_entity)
        expect(call.reload.live).to be_nil
      end

      it 'rejects an unknown message role' do
        put_live({ live: live_payload[:live].merge(transcript: [{ kind: 'message', role: 'system', content: 'hi' }]) })

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'rejects a missing or non-integer seq' do
        put_live({ live: live_payload[:live].except(:seq) })
        expect(response).to have_http_status(:unprocessable_entity)

        put_live({ live: live_payload[:live].merge(seq: '12') })
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'rejects negative counters and a non-boolean transfer_failed' do
        put_live({ live: live_payload[:live].merge(interruptions: -1) })
        expect(response).to have_http_status(:unprocessable_entity)

        put_live({ live: live_payload[:live].merge(transfer_failed: 'yes') })
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'rejects a request without a live object' do
        put_live({ seq: 1 })

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'returns not found for a call from another provider' do
        twilio_call = create(:call, account: account, conversation: conversation, inbox: conversation.inbox,
                                    contact: conversation.contact)

        put "/api/v1/accounts/#{account.id}/pathors/calls/#{twilio_call.id}/live",
            params: live_payload, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/pathors/calls/active' do
    let(:active_url) { "/api/v1/accounts/#{account.id}/pathors/calls/active" }
    let(:other_conversation) { create(:conversation, account: account) }
    let!(:live_call) do
      create(:call, :pathors, account: account, conversation: conversation, inbox: conversation.inbox,
                              contact: conversation.contact, started_at: 2.minutes.ago,
                              live: { 'seq' => 1, 'turns' => 4, 'interruptions' => 1, 'transfer_failed' => false,
                                      'transcript' => [{ 'kind' => 'message', 'role' => 'user', 'content' => 'hi' }] })
    end
    let!(:ringing_call) do
      create(:call, :pathors, account: account, conversation: conversation, inbox: conversation.inbox,
                              contact: conversation.contact, status: 'ringing', started_at: 5.minutes.ago)
    end
    let!(:other_inbox_call) do
      create(:call, :pathors, account: account, conversation: other_conversation, inbox: other_conversation.inbox,
                              contact: other_conversation.contact, started_at: 1.minute.ago)
    end

    before do
      create(:call, :pathors, account: account, conversation: conversation, inbox: conversation.inbox,
                              contact: conversation.contact, status: 'completed')
      create(:call, account: account, conversation: conversation, inbox: conversation.inbox,
                    contact: conversation.contact, status: 'in_progress')
      other_account = create(:account)
      other_account_conversation = create(:conversation, account: other_account)
      create(:call, :pathors, account: other_account, conversation: other_account_conversation,
                              inbox: other_account_conversation.inbox, contact: other_account_conversation.contact)
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get active_url, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an administrator' do
      it 'lists every live pathors call in the account, oldest first' do
        get active_url, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:ok)
        ids = response.parsed_body['payload'].pluck('id')
        expect(ids).to eq([ringing_call.id, live_call.id, other_inbox_call.id])
      end

      it 'ends a call still live past the maximum duration instead of listing it' do
        message = create(:message, account: account, conversation: conversation, inbox: conversation.inbox,
                                   content_type: :voice_call, updated_at: 3.hours.ago)
        stale_call = create(:call, :pathors, account: account, conversation: conversation, inbox: conversation.inbox,
                                             contact: conversation.contact, message: message, started_at: 3.hours.ago)

        get active_url, headers: admin.create_new_auth_token, as: :json

        expect(response.parsed_body['payload'].pluck('id')).not_to include(stale_call.id)
        expect(stale_call.reload).to have_attributes(status: 'completed', end_reason: 'stale', ended_at: nil)
        expect(message.reload.updated_at).to be > 1.minute.ago
      end

      it 'carries what the list row and the bubble need, transcript included' do
        get active_url, headers: admin.create_new_auth_token, as: :json

        row = response.parsed_body['payload'].find { |item| item['id'] == live_call.id }
        expect(row).to include(
          'status' => 'in-progress',
          'conversation_id' => conversation.display_id,
          'inbox_id' => conversation.inbox_id,
          'inbox_name' => conversation.inbox.name,
          'contact_name' => conversation.contact.name,
          'live' => { 'seq' => 1, 'turns' => 4, 'interruptions' => 1, 'transfer_failed' => false,
                      'transcript' => [{ 'kind' => 'message', 'role' => 'user', 'content' => 'hi' }] }
        )
      end
    end

    context 'when it is an agent' do
      it 'lists only the calls in inboxes the agent belongs to' do
        create(:inbox_member, user: agent, inbox: conversation.inbox)

        get active_url, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['payload'].pluck('id')).to contain_exactly(ringing_call.id, live_call.id)
      end

      it 'lists nothing for an agent without inbox access' do
        get active_url, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['payload']).to eq([])
      end
    end
  end
end
