require 'rails_helper'

describe Integrations::Github::ProcessorService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Ada Lovelace', email: 'ada@example.com') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:hook) { create(:integrations_hook, :github, account: account) }
  let(:ticket) { create(:ticket, conversation: conversation, subject: 'Refund never arrived', ticket_type: 'issue') }
  let(:issues_url) { 'https://api.github.com/repos/pathorsAI/chatwoot/issues' }
  let(:tokens_url) { 'https://api.github.com/app/installations/4242/access_tokens' }
  let(:issue_response) do
    { 'html_url' => 'https://github.com/pathorsAI/chatwoot/issues/42', 'number' => 42 }
  end

  before do
    allow(GlobalConfigService).to receive(:load).and_call_original
    allow(GlobalConfigService).to receive(:load).with('GITHUB_APP_ID', nil).and_return('123456')
    allow(GlobalConfigService).to receive(:load).with('GITHUB_APP_PRIVATE_KEY', nil).and_return(OpenSSL::PKey::RSA.generate(2048).to_pem)
    stub_request(:post, tokens_url)
      .to_return(status: 201, body: { token: 'ghs_installation_token', expires_at: 1.hour.from_now.iso8601 }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  describe '#perform' do
    context 'when a ticket is created' do
      before do
        create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                         content: 'I paid last week and the refund never showed up.')
      end

      it 'opens a github issue with the ticket context' do
        stub_request(:post, issues_url).to_return(status: 201, body: issue_response.to_json,
                                                  headers: { 'Content-Type' => 'application/json' })

        described_class.new(hook: hook, event_name: 'ticket.created', event_data: { ticket: ticket }).perform

        expect(WebMock).to have_requested(:post, issues_url)
          .with(headers: { 'Authorization' => 'Bearer ghs_installation_token', 'X-GitHub-Api-Version' => '2022-11-28' }) { |request|
            body = JSON.parse(request.body)
            expect(body['title']).to eq('Refund never arrived')
            expect(body['body']).to include('Ada Lovelace <ada@example.com>')
            expect(body['body']).to include('issue')
            expect(body['body']).to include("/app/accounts/#{account.id}/conversations/#{conversation.display_id}")
            expect(body['body']).to include('I paid last week and the refund never showed up.')
            expect(body).not_to have_key('labels')
            true
          }
      end

      it 'stores the issue on the conversation and posts a private note' do
        stub_request(:post, issues_url).to_return(status: 201, body: issue_response.to_json,
                                                  headers: { 'Content-Type' => 'application/json' })

        described_class.new(hook: hook, event_name: 'ticket.created', event_data: { ticket: ticket }).perform

        expect(conversation.reload.additional_attributes['github_issue']).to eq(
          'url' => 'https://github.com/pathorsAI/chatwoot/issues/42',
          'number' => 42,
          'repository' => 'pathorsAI/chatwoot'
        )
        note = conversation.messages.where(private: true).last
        expect(note.content).to include('https://github.com/pathorsAI/chatwoot/issues/42')
      end

      it 'applies the configured label' do
        hook.update!(settings: hook.settings.merge('label' => 'support'))
        stub_request(:post, issues_url).to_return(status: 201, body: issue_response.to_json,
                                                  headers: { 'Content-Type' => 'application/json' })

        described_class.new(hook: hook, event_name: 'ticket.created', event_data: { ticket: ticket }).perform

        expect(WebMock).to(have_requested(:post, issues_url)
          .with { |request| JSON.parse(request.body)['labels'] == ['support'] })
      end
    end

    context 'when the conversation already has an issue' do
      it 'does not call the github api' do
        conversation.update!(additional_attributes: { 'github_issue' => { 'number' => 7 } })

        described_class.new(hook: hook, event_name: 'ticket.created', event_data: { ticket: ticket }).perform

        expect(WebMock).not_to have_requested(:post, issues_url)
      end
    end

    context 'when the event is not a ticket creation' do
      it 'does not call the github api' do
        described_class.new(hook: hook, event_name: 'ticket.updated', event_data: { ticket: ticket }).perform

        expect(WebMock).not_to have_requested(:post, issues_url)
      end
    end

    context 'when no repository has been picked yet' do
      it 'does not call github at all' do
        hook.update!(settings: {})

        described_class.new(hook: hook, event_name: 'ticket.created', event_data: { ticket: ticket }).perform

        expect(WebMock).not_to have_requested(:post, tokens_url)
        expect(WebMock).not_to have_requested(:post, issues_url)
      end
    end

    context 'when the hook predates the GitHub App' do
      it 'does not call github at all' do
        hook.update!(reference_id: nil)

        described_class.new(hook: hook, event_name: 'ticket.created', event_data: { ticket: ticket }).perform

        expect(WebMock).not_to have_requested(:post, tokens_url)
      end
    end

    context 'when the hook is waiting for a reconnect' do
      it 'does not call github at all' do
        hook.prompt_reauthorization!

        described_class.new(hook: hook, event_name: 'ticket.created', event_data: { ticket: ticket }).perform

        expect(WebMock).not_to have_requested(:post, tokens_url)
      end
    end

    context 'when the app no longer reaches the repository' do
      it 'asks for a reconnect without raising or recording an issue' do
        stub_request(:post, issues_url).to_return(status: 404, body: { message: 'Not Found' }.to_json,
                                                  headers: { 'Content-Type' => 'application/json' })

        expect do
          described_class.new(hook: hook, event_name: 'ticket.created', event_data: { ticket: ticket }).perform
        end.not_to raise_error

        expect(hook.reauthorization_required?).to be(true)
        expect(conversation.reload.additional_attributes['github_issue']).to be_nil
      end
    end

    context 'when github throttles the request' do
      it 'keeps the hook connected' do
        stub_request(:post, issues_url).to_return(status: 403, body: { message: 'secondary rate limit' }.to_json,
                                                  headers: { 'Content-Type' => 'application/json', 'Retry-After' => '60' })

        described_class.new(hook: hook, event_name: 'ticket.created', event_data: { ticket: ticket }).perform

        expect(hook.reauthorization_required?).to be(false)
      end
    end

    context 'when the installation is gone' do
      it 'asks for a reconnect without raising' do
        stub_request(:post, tokens_url).to_return(status: 404, body: { message: 'Not Found' }.to_json,
                                                  headers: { 'Content-Type' => 'application/json' })

        expect do
          described_class.new(hook: hook, event_name: 'ticket.created', event_data: { ticket: ticket }).perform
        end.not_to raise_error

        expect(hook.reauthorization_required?).to be(true)
        expect(WebMock).not_to have_requested(:post, issues_url)
      end
    end

    context 'when github rejects the issue itself' do
      it 'logs the failure and keeps the hook connected' do
        stub_request(:post, issues_url).to_return(status: 422, body: { message: 'Validation Failed' }.to_json,
                                                  headers: { 'Content-Type' => 'application/json' })
        allow(Rails.logger).to receive(:error)

        described_class.new(hook: hook, event_name: 'ticket.created', event_data: { ticket: ticket }).perform

        expect(Rails.logger).to have_received(:error).with(/422.*Validation Failed/)
        expect(hook.reauthorization_required?).to be(false)
      end
    end
  end
end
