# frozen_string_literal: true

RSpec.describe Administrate::MCP::OAuthAccessToken do
  describe 'validations' do
    subject { create(:administrate_mcp_oauth_access_token) }

    it do
      is_expected.to belong_to(:admin)
      is_expected.to belong_to(:application).class_name('Administrate::MCP::OAuthApplication')
      is_expected.to validate_presence_of(:token_digest)
      is_expected.to validate_uniqueness_of(:token_digest)
      is_expected.to validate_presence_of(:refresh_token_digest)
      is_expected.to validate_uniqueness_of(:refresh_token_digest)
      is_expected.to validate_presence_of(:expires_in)
    end
  end

  describe '.generate_token' do
    it 'generates 64-character hex strings' do
      expect(described_class.generate_token).to match(/\A[0-9a-f]{64}\z/)
      expect(described_class.generate_refresh_token).to match(/\A[0-9a-f]{64}\z/)
    end
  end

  describe '.digest' do
    it 'hashes the plaintext with SHA-256' do
      expect(described_class.digest('a_token')).to eq(Digest::SHA256.hexdigest('a_token'))
    end
  end

  describe '.find_by_token' do
    it 'finds the token by the digest of the presented access token, regardless of revoked or expired state' do
      token = create(:administrate_mcp_oauth_access_token)
      revoked_token = create(:administrate_mcp_oauth_access_token, revoked_at: Time.current)

      expect(described_class.find_by_token(token.plaintext_token)).to eq(token)
      expect(described_class.find_by_token(revoked_token.plaintext_token)).to eq(revoked_token)
    end

    it 'returns nil for a token that does not match any row' do
      expect(described_class.find_by_token('unknown_token')).to be_nil
    end
  end

  describe '.find_by_refresh_token' do
    it 'finds the token by the digest of the presented refresh token' do
      token = create(:administrate_mcp_oauth_access_token)

      expect(described_class.find_by_refresh_token(token.plaintext_refresh_token)).to eq(token)
    end

    it 'returns nil for a refresh token that does not match any row' do
      expect(described_class.find_by_refresh_token('unknown_refresh_token')).to be_nil
    end
  end

  describe '.issue' do
    subject(:token) { described_class.issue(admin:, application:, scopes: '') }

    let(:application) { create(:administrate_mcp_oauth_application) }
    let(:admin) { create(:admin) }

    it 'persists only the digests of the generated access and refresh tokens' do
      expect(token.token_digest).to eq(described_class.digest(token.plaintext_token))
      expect(token.refresh_token_digest).to eq(described_class.digest(token.plaintext_refresh_token))

      persisted = described_class.find(token.id)
      expect(persisted.token_digest).not_to eq(token.plaintext_token)
      expect(persisted.refresh_token_digest).not_to eq(token.plaintext_refresh_token)
    end

    it 'exposes the plaintext values on the returned instance, and only there' do
      expect(token.plaintext_token).to match(/\A[0-9a-f]{64}\z/)
      expect(token.plaintext_refresh_token).to match(/\A[0-9a-f]{64}\z/)

      persisted = described_class.find(token.id)
      expect(persisted.plaintext_token).to be_nil
      expect(persisted.plaintext_refresh_token).to be_nil
    end

    it 'authenticates when the issued access token is presented back' do
      expect(described_class.find_by_token(token.plaintext_token)).to eq(token)
    end

    it 'does not authenticate a token that was never issued' do
      expect(described_class.find_by_token('wrong_token')).to be_nil
    end
  end

  describe '#accessible?' do
    it 'is true while active and false once revoked or expired' do
      expect(create(:administrate_mcp_oauth_access_token)).to be_accessible
      expect(create(:administrate_mcp_oauth_access_token, revoked_at: Time.current)).not_to be_accessible
      expect(create(:administrate_mcp_oauth_access_token, created_at: 2.weeks.ago)).not_to be_accessible
    end
  end

  describe '#revoke!' do
    it 'sets revoked_at' do
      token = create(:administrate_mcp_oauth_access_token)

      expect { token.revoke! }.to change(token, :revoked?).from(false).to(true)
    end
  end

  describe '#reload' do
    it 'drops the plaintext so it lives only on the instance that issued it' do
      token = described_class.issue(
        admin: create(:admin), application: create(:administrate_mcp_oauth_application), scopes: ''
      )

      expect { token.reload }.to change(token, :plaintext_token).to(nil)
      expect(token.plaintext_refresh_token).to be_nil
    end
  end
end
