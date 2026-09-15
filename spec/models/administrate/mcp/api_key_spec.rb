# frozen_string_literal: true

RSpec.describe Administrate::MCP::ApiKey do
  describe 'validations' do
    subject { create(:administrate_mcp_api_key) }

    it do
      is_expected.to belong_to(:admin)
      is_expected.to validate_presence_of(:token_digest)
      is_expected.to validate_uniqueness_of(:token_digest)
      is_expected.to validate_presence_of(:token_prefix)
      is_expected.to validate_presence_of(:name)
    end
  end

  describe '.generate_token' do
    it 'generates a token carrying the configured prefix' do
      token = described_class.generate_token

      expect(token).to start_with('amcp_')
      expect(token.length).to eq(45)
    end

    it 'follows a reconfigured prefix' do
      Administrate::MCP.config.api_key_token_prefix = 'smcp_'

      expect(described_class.generate_token).to start_with('smcp_')
    end
  end

  describe '.authenticate' do
    let(:admin) { create(:admin) }
    let(:token) { described_class.generate_token }
    let!(:api_key) do
      create(
        :administrate_mcp_api_key,
        admin:,
        token_digest: described_class.digest_token(token),
        token_prefix: token[0, 13]
      )
    end

    it 'returns the API key for a valid token' do
      expect(described_class.authenticate(token)).to eq(api_key)
    end

    it 'updates last_used_at' do
      expect { described_class.authenticate(token) }.to change { api_key.reload.last_used_at }.from(nil)
    end

    it 'returns nil for an invalid token' do
      expect(described_class.authenticate('amcp_invalid')).to be_nil
    end

    it 'returns nil for a revoked key' do
      api_key.revoke!

      expect(described_class.authenticate(token)).to be_nil
    end

    it 'returns nil for a token without the prefix' do
      expect(described_class.authenticate('not_a_token')).to be_nil
    end

    it 'returns nil for nil' do
      expect(described_class.authenticate(nil)).to be_nil
    end
  end

  describe '#scopes' do
    it 'is empty for a read-only key and carries the write scope when write access is granted' do
      expect(create(:administrate_mcp_api_key).scopes).to eq([])
      expect(create(:administrate_mcp_api_key, write_access: true).scopes).to eq(['write'])
    end
  end

  describe '#revoke!' do
    it 'sets revoked_at' do
      api_key = create(:administrate_mcp_api_key)

      expect { api_key.revoke! }.to change(api_key, :revoked?).from(false).to(true)
    end
  end
end
