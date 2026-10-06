require 'rails_helper'

describe Integrations::Github::AppClient do
  subject(:client) { described_class.new }

  let(:private_key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:tokens_url) { 'https://api.github.com/app/installations/4242/access_tokens' }
  let(:token_response) { { token: 'ghs_installation_token', expires_at: 1.hour.from_now.iso8601 } }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }

  before do
    allow(GlobalConfigService).to receive(:load).and_call_original
    {
      'GITHUB_APP_ID' => '123456',
      'GITHUB_APP_CLIENT_ID' => 'Iv1.client',
      'GITHUB_APP_CLIENT_SECRET' => 'client-secret',
      'GITHUB_APP_PRIVATE_KEY' => private_key.to_pem
    }.each { |key, value| allow(GlobalConfigService).to receive(:load).with(key, nil).and_return(value) }
  end

  describe '#installation_token' do
    it 'signs an app JWT with the private key and returns the installation token' do
      stub_request(:post, tokens_url).to_return(status: 201, body: token_response.to_json, headers: json_headers)

      expect(client.installation_token(4242)).to eq('ghs_installation_token')

      expect(WebMock).to(have_requested(:post, tokens_url).with do |request|
        jwt = request.headers['Authorization'].delete_prefix('Bearer ')
        payload, header = JWT.decode(jwt, private_key.public_key, true, algorithm: 'RS256')
        header['alg'] == 'RS256' && payload['iss'] == '123456' && request.body.blank?
      end)
    end

    it 'scopes the token to the repository and to issues when a repository is given' do
      stub_request(:post, tokens_url).to_return(status: 201, body: token_response.to_json, headers: json_headers)

      client.installation_token(4242, repository: 'pathorsAI/pathors')

      expect(WebMock).to have_requested(:post, tokens_url)
        .with(body: { repositories: ['pathors'], permissions: { issues: 'write' } }.to_json)
    end

    it 'reuses a cached token until five minutes before it expires' do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
      stub_request(:post, tokens_url).to_return(status: 201, body: token_response.to_json, headers: json_headers)

      freeze_time do
        2.times { client.installation_token(4242) }
        expect(WebMock).to have_requested(:post, tokens_url).once

        travel 54.minutes
        client.installation_token(4242)
        expect(WebMock).to have_requested(:post, tokens_url).once

        travel 2.minutes
        client.installation_token(4242)
        expect(WebMock).to have_requested(:post, tokens_url).twice
      end
    end

    it 'raises an authorization error when the installation is gone' do
      stub_request(:post, tokens_url).to_return(status: 404, body: { message: 'Not Found' }.to_json, headers: json_headers)

      expect { client.installation_token(4242) }.to raise_error(described_class::AuthorizationError, /404/)
    end
  end

  describe '#repositories' do
    it 'follows pagination and returns every full name' do
      stub_request(:post, tokens_url).to_return(status: 201, body: token_response.to_json, headers: json_headers)
      stub_request(:get, 'https://api.github.com/installation/repositories?per_page=100')
        .with(headers: { 'Authorization' => 'Bearer ghs_installation_token' })
        .to_return(status: 200, body: { repositories: [{ full_name: 'pathorsAI/pathors' }] }.to_json,
                   headers: json_headers.merge('Link' => '<https://api.github.com/installation/repositories?per_page=100&page=2>; rel="next"'))
      stub_request(:get, 'https://api.github.com/installation/repositories?per_page=100&page=2')
        .to_return(status: 200, body: { repositories: [{ full_name: 'pathorsAI/inbox' }] }.to_json, headers: json_headers)

      expect(client.repositories(4242)).to eq(%w[pathorsAI/pathors pathorsAI/inbox])
    end
  end

  describe '#exchange_code' do
    it 'returns the user token' do
      stub_request(:post, 'https://github.com/login/oauth/access_token')
        .with(body: { client_id: 'Iv1.client', client_secret: 'client-secret', code: 'oauth-code' })
        .to_return(status: 200, body: { access_token: 'ghu_user_token' }.to_json, headers: json_headers)

      expect(client.exchange_code('oauth-code')).to eq('ghu_user_token')
    end

    it 'raises when GitHub rejects the code' do
      stub_request(:post, 'https://github.com/login/oauth/access_token')
        .to_return(status: 200, body: { error: 'bad_verification_code' }.to_json, headers: json_headers)

      expect { client.exchange_code('stale') }.to raise_error(described_class::Error, /bad_verification_code/)
    end
  end

  describe '#user_installation_ids' do
    it 'lists the installations the user can see' do
      stub_request(:get, 'https://api.github.com/user/installations?per_page=100')
        .with(headers: { 'Authorization' => 'Bearer ghu_user_token' })
        .to_return(status: 200, body: { installations: [{ id: 4242 }, { id: 7 }] }.to_json, headers: json_headers)

      expect(client.user_installation_ids('ghu_user_token')).to eq([4242, 7])
    end
  end
end
