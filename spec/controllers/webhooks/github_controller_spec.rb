require 'rails_helper'

RSpec.describe Webhooks::GithubController, type: :request do
  let(:account) { create(:account) }
  let!(:hook) { create(:integrations_hook, :github, account: account, reference_id: '4242') }
  let(:webhook_secret) { 'github-webhook-secret' }
  let(:event) { 'installation' }
  let(:payload) { { action: 'deleted', installation: { id: 4242 } } }
  let(:body) { payload.to_json }
  let(:signature) { "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', webhook_secret, body)}" }
  let(:headers) { { 'CONTENT_TYPE' => 'application/json', 'X-GitHub-Event' => event, 'X-Hub-Signature-256' => signature } }

  before do
    allow(GlobalConfigService).to receive(:load).and_call_original
    allow(GlobalConfigService).to receive(:load).with('GITHUB_APP_WEBHOOK_SECRET', nil).and_return(webhook_secret)
  end

  it 'rejects a payload signed with another secret' do
    post '/webhooks/github', params: body,
                             headers: headers.merge('X-Hub-Signature-256' => "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', 'wrong', body)}")

    expect(response).to have_http_status(:unauthorized)
    expect(hook.reauthorization_required?).to be(false)
  end

  it 'rejects every payload when no webhook secret is configured' do
    allow(GlobalConfigService).to receive(:load).with('GITHUB_APP_WEBHOOK_SECRET', nil).and_return(nil)

    post '/webhooks/github', params: body, headers: headers

    expect(response).to have_http_status(:unauthorized)
  end

  it 'asks for a reconnect when the app is uninstalled, and stays that way on replay' do
    2.times { post '/webhooks/github', params: body, headers: headers }

    expect(response).to have_http_status(:ok)
    expect(hook.reauthorization_required?).to be(true)
  end

  it 'leaves hooks of other installations alone' do
    other = create(:integrations_hook, :github, account: create(:account), reference_id: '7')

    post '/webhooks/github', params: body, headers: headers

    expect(other.reauthorization_required?).to be(false)
  end

  context 'when a suspended installation is unsuspended' do
    let(:payload) { { action: 'unsuspend', installation: { id: 4242 } } }

    it 'clears the reconnect prompt' do
      hook.prompt_reauthorization!

      post '/webhooks/github', params: body, headers: headers

      expect(hook.reauthorization_required?).to be(false)
    end
  end

  context 'when repositories are removed from the installation' do
    let(:event) { 'installation_repositories' }
    let(:removed) { [{ full_name: 'PathorsAI/Chatwoot' }] }
    let(:payload) { { action: 'removed', installation: { id: 4242 }, repositories_removed: removed } }

    it 'asks for a reconnect when the selected repository is among them' do
      post '/webhooks/github', params: body, headers: headers

      expect(hook.reauthorization_required?).to be(true)
    end

    context 'when the selected repository is still granted' do
      let(:removed) { [{ full_name: 'pathorsAI/other' }] }

      it 'keeps the hook working' do
        post '/webhooks/github', params: body, headers: headers

        expect(hook.reauthorization_required?).to be(false)
      end
    end
  end

  context 'with an event the integration does not handle' do
    let(:event) { 'push' }

    it 'acknowledges it' do
      post '/webhooks/github', params: body, headers: headers

      expect(response).to have_http_status(:ok)
      expect(hook.reauthorization_required?).to be(false)
    end
  end
end
