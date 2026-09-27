require 'rails_helper'

describe Pathors::CallHangupService do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account) }
  let(:call) do
    create(:call, :pathors, account: account, conversation: conversation, inbox: conversation.inbox,
                            contact: conversation.contact)
  end
  let!(:agent_bot) do
    create(:agent_bot, account: account,
                       outgoing_url: 'https://api.pathors.example/project/proj_42/integration/chatwoot/callback')
  end
  let(:hangup_url) { 'https://api.pathors.example/project/proj_42/integration/chatwoot/voice/hangup' }
  let(:expected_body) do
    {
      action: 'hangup',
      sessionId: call.provider_call_id,
      conversationId: conversation.display_id,
      agent: { id: agent.id, name: agent.available_name },
      requestId: 'req-1'
    }.to_json
  end

  def stub_hangup(status: 200, body: { ok: true })
    stub_request(:post, hangup_url).to_return(
      status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' }
    )
  end

  def perform
    described_class.new(call: call, user: agent).perform
  end

  # Fixtures first: the factories draw from SecureRandom.uuid too.
  def stub_request_id
    call
    allow(SecureRandom).to receive(:uuid).and_return('req-1')
  end

  describe 'request signing' do
    it 'sends a unix-seconds timestamp and signs "<timestamp>.<body>" with the bot secret' do
      stub_hangup
      stub_request_id

      freeze_time do
        perform

        timestamp = Time.current.to_i.to_s
        signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', agent_bot.secret, "#{timestamp}.#{expected_body}")}"
        expect(
          a_request(:post, hangup_url).with(
            body: expected_body,
            headers: { 'X-Pathors-Timestamp' => timestamp, 'X-Pathors-Signature' => signature }
          )
        ).to have_been_made.once
      end
    end

    it 'produces a different signature for the same body at a different time' do
      signatures = []
      stub_request(:post, hangup_url).to_return do |request|
        signatures << request.headers['X-Pathors-Signature']
        { status: 200, body: { ok: true }.to_json, headers: { 'Content-Type' => 'application/json' } }
      end

      perform
      travel_to(1.minute.from_now) { perform }

      expect(signatures.size).to eq(2)
      expect(signatures.uniq.size).to eq(2)
    end

    it 'produces a different signature for two hangups within the same second' do
      signatures = []
      stub_request(:post, hangup_url).to_return do |request|
        signatures << request.headers['X-Pathors-Signature']
        { status: 200, body: { ok: true }.to_json, headers: { 'Content-Type' => 'application/json' } }
      end

      freeze_time do
        perform
        perform
      end

      # The backend treats a reused signature as a replay; the per-request id is
      # what keeps a quick retry from colliding with the first attempt.
      expect(signatures.size).to eq(2)
      expect(signatures.uniq.size).to eq(2)
    end

    it 'signs with the access token when the bot has no secret' do
      agent_bot.update_column(:secret, nil) # rubocop:disable Rails/SkipsModelValidations
      stub_hangup
      stub_request_id

      freeze_time do
        perform

        timestamp = Time.current.to_i.to_s
        token = agent_bot.access_token.token
        signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', token, "#{timestamp}.#{expected_body}")}"
        expect(
          a_request(:post, hangup_url).with(headers: { 'X-Pathors-Signature' => signature })
        ).to have_been_made.once
      end
    end
  end

  describe 'status relaying' do
    it 'relays a 200 as success' do
      stub_hangup

      result = perform

      expect(result).to be_ok
      expect(result.status).to eq(200)
      expect(result.body).to eq('ok' => true)
    end

    it 'relays a 404 call_not_found verbatim' do
      stub_hangup(status: 404, body: { error: 'call_not_found' })

      result = perform

      expect(result.status).to eq(404)
      expect(result.body).to eq('error' => 'call_not_found')
    end

    it 'relays a 409 not_call_owner verbatim' do
      stub_hangup(status: 409, body: { error: 'not_call_owner' })

      result = perform

      expect(result.status).to eq(409)
      expect(result.body).to eq('error' => 'not_call_owner')
    end

    it 'reports a rejected signature as pathors_auth_failed' do
      stub_hangup(status: 401, body: { error: 'unauthorized' })

      result = perform

      expect(result.status).to eq(502)
      expect(result.body).to eq(error: 'pathors_auth_failed')
    end

    it 'collapses any other upstream status into pathors_error' do
      stub_hangup(status: 500, body: { error: 'terminate_failed' })

      result = perform

      expect(result.status).to eq(502)
      expect(result.body).to eq(error: 'pathors_error')
    end

    it 'reports a timeout as pathors_unreachable' do
      stub_request(:post, hangup_url).to_timeout

      result = perform

      expect(result.status).to eq(502)
      expect(result.body).to eq(error: 'pathors_unreachable')
    end

    it 'returns pathors_not_configured without a pathors agent bot' do
      agent_bot.update!(outgoing_url: 'https://example.com/other')

      result = perform

      expect(result.status).to eq(422)
      expect(result.body).to eq(error: 'pathors_not_configured')
      expect(a_request(:post, hangup_url)).not_to have_been_made
    end
  end
end
