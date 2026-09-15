# frozen_string_literal: true

RSpec.describe Administrate::MCP::Authentication do
  describe '.authenticate!' do
    let(:admin) { create(:admin) }
    let(:token) { Administrate::MCP::ApiKey.generate_token }
    let!(:api_key) do
      create(
        :administrate_mcp_api_key,
        admin:,
        token_digest: Administrate::MCP::ApiKey.digest_token(token),
        token_prefix: token[0, 13]
      )
    end
    let(:request) { instance_double(ActionDispatch::Request, headers:) }

    context 'with a valid bearer token' do
      let(:headers) { { 'Authorization' => "Bearer #{token}" } }

      it 'returns the admin with no scopes (API keys are read-only by default)' do
        identity = described_class.authenticate!(request)

        expect(identity.admin).to eq(admin)
        expect(identity.scopes).to eq([])
      end

      context 'when the key has write access' do
        before { api_key.update!(write_access: true) }

        it 'returns the write scope' do
          expect(described_class.authenticate!(request).scopes).to eq(['write'])
        end
      end
    end

    context 'with no authorization header' do
      let(:headers) { {} }

      it 'raises an error' do
        expect { described_class.authenticate!(request) }.to raise_error(
          described_class::Error,
          'Missing Authorization header'
        )
      end
    end

    context 'with an invalid API key token' do
      let(:headers) { { 'Authorization' => 'Bearer amcp_invalid' } }

      it 'raises an InvalidApiKeyError' do
        expect { described_class.authenticate!(request) }.to raise_error(
          described_class::InvalidApiKeyError,
          'Invalid or revoked API key'
        )
      end
    end

    context 'with a revoked API key' do
      let(:headers) { { 'Authorization' => "Bearer #{token}" } }

      before { api_key.revoke! }

      it 'raises an InvalidApiKeyError' do
        expect { described_class.authenticate!(request) }.to raise_error(
          described_class::InvalidApiKeyError,
          'Invalid or revoked API key'
        )
      end
    end

    context 'with a valid OAuth access token' do
      let(:oauth_token) { create(:administrate_mcp_oauth_access_token, admin:, scopes: 'write') }
      let(:headers) { { 'Authorization' => "Bearer #{oauth_token.token}" } }

      it 'returns the admin with the token scopes' do
        identity = described_class.authenticate!(request)

        expect(identity.admin).to eq(admin)
        expect(identity.scopes).to eq(['write'])
      end
    end

    context 'with an expired OAuth access token' do
      let(:oauth_token) { create(:administrate_mcp_oauth_access_token, admin:, created_at: 2.weeks.ago) }
      let(:headers) { { 'Authorization' => "Bearer #{oauth_token.token}" } }

      it 'raises an OAuthTokenError' do
        expect { described_class.authenticate!(request) }.to raise_error(
          described_class::OAuthTokenError,
          'Token has expired'
        )
      end
    end

    context 'with a revoked OAuth access token' do
      let(:oauth_token) { create(:administrate_mcp_oauth_access_token, admin:, revoked_at: Time.current) }
      let(:headers) { { 'Authorization' => "Bearer #{oauth_token.token}" } }

      it 'raises an OAuthTokenError' do
        expect { described_class.authenticate!(request) }.to raise_error(
          described_class::OAuthTokenError,
          'Token has been revoked'
        )
      end
    end

    context 'with an unknown OAuth token' do
      let(:headers) { { 'Authorization' => 'Bearer unknown_oauth_token_value' } }

      it 'raises an OAuthTokenError' do
        expect { described_class.authenticate!(request) }.to raise_error(
          described_class::OAuthTokenError,
          'Invalid token'
        )
      end
    end
  end
end
