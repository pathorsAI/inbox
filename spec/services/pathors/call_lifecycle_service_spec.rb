require 'rails_helper'

RSpec.describe Pathors::CallLifecycleService do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:bot_inbox) { create(:agent_bot_inbox, inbox: create(:inbox, account: account)) }
  # Created the way a mirrored call's conversation is: pending under the bot.
  let(:conversation) { create(:conversation, account: account, inbox: bot_inbox.inbox) }
  let(:call) do
    create(:call, :pathors, account: account, conversation: conversation, inbox: conversation.inbox,
                            contact: conversation.contact, from_number: '+886912345678')
  end
  let(:service) { described_class.new(call: call) }
  let(:request_at) { 1_760_000_000_000 }

  def set_attention(attention, transfer_failed: false)
    call.update!(live: { 'seq' => 1, 'transfer_failed' => transfer_failed, 'transcript' => [], 'attention' => attention })
  end

  def takeover_request(at: request_at)
    { 'reason' => 'looping', 'detail' => 'stuck', 'source' => 'agent', 'at' => at }
  end

  before { create(:inbox_member, user: agent, inbox: conversation.inbox) }

  describe '#live_updated' do
    it 'starts from a pending, bot-held conversation' do
      expect(conversation).to have_attributes(status: 'pending', ai_assignee: bot_inbox.agent_bot)
    end

    it 'hands the conversation to humans when the AI asks for help' do
      set_attention({ 'takeover_request' => takeover_request })
      allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

      service.live_updated

      expect(call.reload).to have_attributes(needs_action: true, takeover_requested: true)
      expect(conversation.reload).to have_attributes(status: 'open', assignee_agent_bot_id: nil, assignee_id: nil)
      expect(conversation.custom_attributes).to include('pathors_takeover_requested' => true, 'pathors_call_from' => '+886912345678')
      expect(Rails.configuration.dispatcher).to have_received(:dispatch)
        .with(Events::Types::CONVERSATION_BOT_HANDOFF, anything, hash_including(conversation: conversation))
    end

    it 'clears the bot from a conversation that is already open' do
      conversation.update!(status: :open)
      set_attention({ 'takeover_request' => takeover_request })

      service.live_updated

      expect(conversation.reload).to have_attributes(status: 'open', assignee_agent_bot_id: nil)
    end

    it 'never takes a conversation away from a human assignee' do
      conversation.update!(assignee: agent)
      set_attention({ 'takeover_request' => takeover_request })

      service.live_updated

      expect(call.reload.needs_action).to be(true)
      expect(conversation.reload.assignee_id).to eq(agent.id)
    end

    it 'does not hand over twice for the same request' do
      set_attention({ 'takeover_request' => takeover_request })
      service.live_updated
      conversation.reload.update!(status: :pending)

      service.live_updated

      expect(conversation.reload.status).to eq('pending')
    end

    %w[dialing connected].each do |phase|
      it "waits while a transfer is #{phase}" do
        set_attention({ 'takeover_request' => takeover_request, 'transfer' => { 'phase' => phase, 'at' => request_at } })

        service.live_updated

        expect(call.reload.needs_action).to be(false)
        expect(conversation.reload.status).to eq('pending')
      end
    end

    it 'needs a human when a transfer failed' do
      set_attention({ 'transfer' => { 'phase' => 'failed', 'failure_reason' => 'busy', 'at' => request_at } })

      service.live_updated

      expect(call.reload).to have_attributes(needs_action: true, takeover_requested: nil)
      expect(conversation.reload.status).to eq('open')
      expect(conversation.custom_attributes).not_to have_key('pathors_takeover_requested')
    end

    it 'needs a human when an older backend reports transfer_failed' do
      set_attention(nil, transfer_failed: true)

      service.live_updated

      expect(call.reload.needs_action).to be(true)
    end

    it 'does not need a human for a request a human already answered' do
      call.update!(accepted_by_agent: agent, accepted_at: request_at + 1)
      set_attention({ 'takeover_request' => takeover_request })

      service.live_updated

      expect(call.reload.needs_action).to be(false)
    end

    context 'when the human leaves' do
      let(:message) { create(:message, account: account, conversation: conversation, inbox: conversation.inbox) }

      before do
        call.update!(message: message, accepted_by_agent: agent, accepted_at: request_at + 1_000, human_joined: true)
      end

      it 'releases the call back to the AI and rebroadcasts the bubble' do
        set_attention({ 'takeover_request' => takeover_request, 'human_left_at' => request_at + 5_000 })
        original = message.reload.updated_at

        travel_to(1.minute.from_now) { service.live_updated }

        expect(call.reload).to have_attributes(accepted_by_agent_id: nil, accepted_at: request_at + 1_000)
        expect(message.reload.updated_at).to be > original
        # The request was made before the human joined, so it stays answered.
        expect(call.needs_action).to be(false)
      end

      it 'needs a human again on a new request' do
        set_attention({ 'takeover_request' => takeover_request(at: request_at + 9_000), 'human_left_at' => request_at + 5_000 })

        service.live_updated

        expect(call.reload).to have_attributes(accepted_by_agent_id: nil, needs_action: true)
      end

      it 'ignores a leave that predates the latest join' do
        set_attention({ 'human_left_at' => request_at })

        service.live_updated

        expect(call.reload.accepted_by_agent_id).to eq(agent.id)
      end
    end
  end

  describe '#joined' do
    it 'records the join and assigns the bot-held conversation to the joiner' do
      call.update!(needs_action: true)

      freeze_time do
        service.joined(agent)

        expect(call.reload).to have_attributes(accepted_by_agent_id: agent.id, accepted_at: (Time.current.to_f * 1000).to_i,
                                               needs_action: false, human_joined: true)
      end
      expect(conversation.reload).to have_attributes(status: 'open', assignee_id: agent.id, assignee_agent_bot_id: nil)
    end

    it 'keeps an existing human assignee' do
      other = create(:user, account: account, role: :agent)
      conversation.update!(assignee: other)

      service.joined(agent)

      expect(conversation.reload.assignee_id).to eq(other.id)
    end
  end

  describe '#ended' do
    def end_call(status: 'completed', end_reason: nil, duration_seconds: 60, attention: nil, **meta)
      call.update!(status: status, end_reason: end_reason, duration_seconds: duration_seconds, **meta,
                   live: attention && { 'seq' => 1, 'attention' => attention })
      service.ended
      call.reload
    end

    {
      { status: 'no_answer', duration_seconds: 0 } => 'no_answer',
      { end_reason: 'transferred' } => 'transferred',
      { attention: { 'transfer' => { 'phase' => 'connected', 'at' => 1 } } } => 'transferred',
      { end_reason: 'human_takeover' } => 'human',
      { human_joined: true } => 'human',
      { end_reason: 'transfer_failed' } => 'transfer_failed',
      { end_reason: 'transferAbandoned' } => 'transfer_failed',
      { attention: { 'transfer' => { 'phase' => 'failed', 'at' => 1 } } } => 'transfer_failed',
      { end_reason: 'user_hangup', duration_seconds: 8 } => 'hangup',
      { end_reason: 'agent_hangup', duration_seconds: 120 } => 'ai_done',
      { end_reason: 'stale', duration_seconds: nil } => 'ai_done'
    }.each do |attributes, expected|
      it "records #{expected} for #{attributes}" do
        expect(end_call(**attributes).outcome).to eq(expected)
        expect(conversation.reload.custom_attributes['pathors_call_outcome']).to eq(expected)
      end
    end

    it 'resolves a conversation only the AI handled' do
      end_call(end_reason: 'agent_hangup')

      expect(conversation.reload.status).to eq('resolved')
    end

    it 'leaves the conversation to the human who took the call over' do
      service.joined(agent)

      end_call(end_reason: 'agent_hangup')

      expect(call.outcome).to eq('human')
      expect(conversation.reload).to have_attributes(status: 'open', assignee_id: agent.id)
    end

    it 'flags a follow-up and keeps the conversation open for an unmet request' do
      set_attention({ 'takeover_request' => takeover_request })
      service.live_updated

      ended = end_call(end_reason: 'user_hangup', attention: { 'takeover_request' => takeover_request })

      expect(ended).to have_attributes(follow_up: true, needs_action: false)
      expect(conversation.reload).to have_attributes(status: 'open', assignee_agent_bot_id: nil)
    end

    it 'opens a still-pending conversation when the request is unmet at the end' do
      call.update!(needs_action: true)

      end_call(end_reason: 'user_hangup')

      expect(call.follow_up).to be(true)
      expect(conversation.reload).to have_attributes(status: 'open', assignee_agent_bot_id: nil)
    end

    it 'keeps the follow-up when the end is reported again' do
      call.update!(needs_action: true)
      end_call(end_reason: 'user_hangup')

      end_call(status: 'failed', end_reason: 'user_hangup')

      expect(call.follow_up).to be(true)
    end

    it 'records the outcome without raising when the account refuses the resolve' do
      account.enable_features('conversation_required_attributes')
      create(:custom_attribute_definition, account: account, attribute_key: 'refund_amount', attribute_model: 'conversation_attribute')
      account.update!(settings: account.settings.to_h.merge('conversation_required_attributes' => ['refund_amount']))

      expect { end_call(end_reason: 'agent_hangup') }.not_to raise_error

      expect(conversation.reload.status).to eq('pending')
      expect(conversation.custom_attributes['pathors_call_outcome']).to eq('ai_done')
    end
  end

  describe '#dismiss' do
    it 'adds the user once' do
      2.times { service.dismiss(agent) }

      expect(call.reload.dismissed_by).to eq([agent.id])
    end
  end
end
