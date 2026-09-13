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
        expect(response.parsed_body['meta']).to eq('count' => 1, 'current_page' => 1, 'total_pages' => 1)
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
  end
end
