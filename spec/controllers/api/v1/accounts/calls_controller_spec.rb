require 'rails_helper'

RSpec.describe 'Calls API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  describe 'GET /api/v1/accounts/{account.id}/calls' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/calls"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an administrator' do
      let!(:call) do
        create(:call, :pathors,
               account: account, conversation: conversation, inbox: inbox,
               contact: conversation.contact, accepted_by_agent: agent,
               duration_seconds: 42, recording_url: 'https://cdn.pathors.example/a.mp3')
      end

      it 'lists the calls of the account in their display form' do
        get "/api/v1/accounts/#{account.id}/calls", headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['meta']).to eq('count' => 1, 'current_page' => 1, 'total_pages' => 1,
                                                   'counts' => { 'need' => 0, 'live' => 1 })
        expect(response.parsed_body['payload'].first).to include(
          'id' => call.id,
          'status' => 'in-progress',
          'direction' => 'inbound',
          'duration_seconds' => 42,
          'recording_url' => 'https://cdn.pathors.example/a.mp3'
        )
      end

      it 'renders the contact, inbox, agent and conversation the list needs' do
        get "/api/v1/accounts/#{account.id}/calls", headers: admin.create_new_auth_token, as: :json

        payload = response.parsed_body['payload'].first
        expect(payload['contact']['id']).to eq(conversation.contact.id)
        expect(payload['inbox']).to include('id' => inbox.id, 'name' => inbox.name, 'channel_type' => inbox.channel_type)
        expect(payload['agent']['name']).to eq(agent.available_name)
        expect(payload['conversation']['display_id']).to eq(conversation.display_id)
      end

      it 'renders a call whose contact was deleted' do
        call.contact.destroy!

        get "/api/v1/accounts/#{account.id}/calls", headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['payload'].first['contact']).to be_nil
      end

      it 'filters by direction' do
        get "/api/v1/accounts/#{account.id}/calls", params: { direction: 'outbound' },
                                                    headers: admin.create_new_auth_token, as: :json

        expect(response.parsed_body['payload']).to be_empty
      end

      it 'filters by status' do
        get "/api/v1/accounts/#{account.id}/calls", params: { status: 'in-progress' },
                                                    headers: admin.create_new_auth_token, as: :json

        expect(response.parsed_body['payload'].pluck('id')).to eq([call.id])
      end
    end

    context 'when it is an agent' do
      let(:other_inbox) { create(:inbox, account: account) }
      let(:other_conversation) { create(:conversation, account: account, inbox: other_inbox) }

      let!(:visible_call) do
        create(:call, account: account, conversation: conversation, inbox: inbox, contact: conversation.contact)
      end
      let!(:hidden_call) do
        create(:call, account: account, conversation: other_conversation, inbox: other_inbox,
                      contact: other_conversation.contact)
      end

      before { create(:inbox_member, user: agent, inbox: inbox) }

      it 'only lists calls from conversations the agent can access' do
        get "/api/v1/accounts/#{account.id}/calls", headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['payload'].pluck('id')).to eq([visible_call.id])
        expect(response.parsed_body['meta']['count']).to eq(1)
        expect(hidden_call.reload).to be_present
      end
    end

    context 'with the calls page filters' do
      let(:contact) { create(:contact, account: account, name: 'Wang Xiaoming', phone_number: '+886912345678') }
      let(:other_contact) { create(:contact, account: account, name: 'Lin', phone_number: '+886223401234') }
      let!(:needs_help) do
        create(:call, :pathors, account: account, conversation: conversation, inbox: inbox, contact: contact,
                                started_at: 10.minutes.ago, needs_action: true, takeover_requested: true,
                                live: { 'seq' => 2, 'attention' => { 'takeover_request' => { 'reason' => 'looping' } } })
      end
      let!(:live_call) do
        create(:call, :pathors, account: account, conversation: conversation, inbox: inbox, contact: other_contact,
                                started_at: 20.minutes.ago)
      end
      let!(:follow_up_call) do
        create(:call, :pathors, account: account, conversation: conversation, inbox: inbox, contact: other_contact,
                                status: 'completed', started_at: 2.days.ago, follow_up: true, outcome: 'transfer_failed',
                                from_number: '+886955000111')
      end
      let!(:done_call) do
        create(:call, :pathors, account: account, conversation: conversation, inbox: inbox, contact: other_contact,
                                status: 'completed', started_at: 3.days.ago, outcome: 'ai_done', accepted_by_agent: agent)
      end

      def list(params = {})
        get "/api/v1/accounts/#{account.id}/calls", params: params, headers: admin.create_new_auth_token, as: :json
        response.parsed_body['payload'].pluck('id')
      end

      it 'segments by what needs a human, what is live and what ended' do
        expect(list(segment: 'need')).to contain_exactly(needs_help.id, follow_up_call.id)
        expect(list(segment: 'live')).to eq([live_call.id, needs_help.id])
        expect(list(segment: 'ended')).to contain_exactly(follow_up_call.id, done_call.id)
      end

      it 'counts the segments regardless of the other filters' do
        list(segment: 'ended', q: 'Wang', since: 1.hour.ago.to_i)

        expect(response.parsed_body['meta']['counts']).to eq('need' => 2, 'live' => 2)
      end

      it 'searches phone numbers typed nationally, by their last digits, or by name' do
        expect(list(q: '0912345678')).to eq([needs_help.id])
        expect(list(q: '5678')).to eq([needs_help.id])
        expect(list(q: '0955-000')).to eq([follow_up_call.id])
        expect(list(q: 'xiao')).to eq([needs_help.id])
        expect(list(q: '%')).to be_empty
      end

      it 'filters by a time window in epoch seconds' do
        expect(list(since: 1.hour.ago.to_i)).to contain_exactly(needs_help.id, live_call.id)
        expect(list(since: 4.days.ago.to_i, until: 1.day.ago.to_i)).to contain_exactly(follow_up_call.id, done_call.id)
      end

      it 'filters by outcome and by a takeover request' do
        expect(list(outcome: 'ai_done')).to eq([done_call.id])
        expect(list(outcome: 'takeover_requested')).to eq([needs_help.id])
      end

      it 'filters to the calls the viewer took over' do
        get "/api/v1/accounts/#{account.id}/calls", params: { mine: true }, headers: agent.create_new_auth_token, as: :json
        expect(response.parsed_body['payload']).to eq([])

        create(:inbox_member, user: agent, inbox: inbox)
        get "/api/v1/accounts/#{account.id}/calls", params: { mine: 'true' }, headers: agent.create_new_auth_token, as: :json
        expect(response.parsed_body['payload'].pluck('id')).to eq([done_call.id])
      end

      it 'rejects unknown filter values' do
        [{ segment: 'all' }, { outcome: 'great' }, { since: 'yesterday' }].each do |params|
          get "/api/v1/accounts/#{account.id}/calls", params: params, headers: admin.create_new_auth_token, as: :json

          expect(response).to have_http_status(:unprocessable_entity)
        end
      end

      it 'renders the handling state and the last live snapshot, ended calls included' do
        follow_up_call.update!(live: { 'seq' => 9, 'transcript' => [{ 'kind' => 'message', 'content' => 'bye' }] },
                               dismissed_by: [admin.id])

        list
        rows = response.parsed_body['payload'].index_by { |row| row['id'] }

        expect(rows[needs_help.id]).to include('needs_action' => true, 'follow_up' => false, 'takeover_requested' => true,
                                               'dismissed' => false, 'accepted_by_agent_name' => 'Pathors AI',
                                               'variables' => nil)
        expect(rows[needs_help.id]['live']['attention']).to eq('takeover_request' => { 'reason' => 'looping' })
        expect(rows[follow_up_call.id]).to include('follow_up' => true, 'outcome' => 'transfer_failed', 'dismissed' => true,
                                                   'from_number' => '+886955000111')
        expect(rows[follow_up_call.id]['live']['transcript']).to eq([{ 'kind' => 'message', 'content' => 'bye' }])
        expect(rows[follow_up_call.id]['conversation']['status']).to eq(conversation.status)
      end

      it 'renders the variables of each handoff card with one message query' do
        cards = [done_call, follow_up_call].map do |call|
          message = create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :activity,
                                     content_type: 'pathors_handoff',
                                     content_attributes: { data: { 'variables' => { 'name' => "caller #{call.id}" } } })
          call.update!(handoff_message_id: message.id)
        end
        expect(cards).to all(be(true))

        message_queries = []
        callback = lambda do |*, payload|
          message_queries << payload[:sql] if payload[:sql].include?('FROM "messages"')
        end
        ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { list }

        rows = response.parsed_body['payload'].index_by { |row| row['id'] }
        expect(rows[done_call.id]['variables']).to eq('name' => "caller #{done_call.id}")
        expect(rows[follow_up_call.id]['variables']).to eq('name' => "caller #{follow_up_call.id}")
        expect(message_queries.size).to eq(1)
      end
    end
  end
end
