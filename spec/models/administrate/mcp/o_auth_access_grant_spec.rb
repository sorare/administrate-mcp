# frozen_string_literal: true

RSpec.describe Administrate::MCP::OAuthAccessGrant do
  describe 'validations' do
    subject { create(:administrate_mcp_oauth_access_grant) }

    it do
      is_expected.to belong_to(:admin)
      is_expected.to belong_to(:application).class_name('Administrate::MCP::OAuthApplication')
      is_expected.to validate_presence_of(:token_digest)
      is_expected.to validate_uniqueness_of(:token_digest)
      is_expected.to validate_presence_of(:redirect_uri)
      is_expected.to validate_presence_of(:code_challenge)
      is_expected.to validate_presence_of(:expires_in)
    end
  end

  describe '.generate_token' do
    it 'generates a 64-character hex string' do
      expect(described_class.generate_token).to match(/\A[0-9a-f]{64}\z/)
    end
  end

  describe '.digest' do
    it 'hashes the plaintext with SHA-256' do
      expect(described_class.digest('a_code')).to eq(Digest::SHA256.hexdigest('a_code'))
    end
  end

  describe '.find_by_token' do
    it 'finds the grant by the digest of the presented code, regardless of revoked or expired state' do
      grant = create(:administrate_mcp_oauth_access_grant)
      revoked_grant = create(:administrate_mcp_oauth_access_grant, revoked_at: Time.current)

      expect(described_class.find_by_token(grant.plaintext_token)).to eq(grant)
      expect(described_class.find_by_token(revoked_grant.plaintext_token)).to eq(revoked_grant)
    end

    it 'returns nil for a code that does not match any grant' do
      expect(described_class.find_by_token('unknown_code')).to be_nil
    end
  end

  describe '.issue' do
    subject(:grant) do
      described_class.issue(
        admin:,
        application:,
        redirect_uri: 'http://localhost:3000/callback',
        code_challenge: Base64.urlsafe_encode64(Digest::SHA256.digest('verifier'), padding: false),
        code_challenge_method: 'S256',
        scopes: ''
      )
    end

    let(:application) { create(:administrate_mcp_oauth_application) }
    let(:admin) { create(:admin) }

    it 'persists only the digest of the generated authorization code' do
      expect(grant.token_digest).to eq(described_class.digest(grant.plaintext_token))
      expect(described_class.find(grant.id).token_digest).not_to eq(grant.plaintext_token)
    end

    it 'exposes the plaintext code on the returned instance, and only there' do
      expect(grant.plaintext_token).to match(/\A[0-9a-f]{64}\z/)
      expect(described_class.find(grant.id).plaintext_token).to be_nil
    end

    it 'authenticates when the issued code is presented back' do
      expect(described_class.find_by_token(grant.plaintext_token)).to eq(grant)
    end
  end

  describe '#expired?' do
    it 'is false within the TTL and true past it' do
      expect(create(:administrate_mcp_oauth_access_grant)).not_to be_expired
      expect(create(:administrate_mcp_oauth_access_grant, created_at: 11.minutes.ago)).to be_expired
    end
  end

  describe '#revoke!' do
    it 'sets revoked_at' do
      grant = create(:administrate_mcp_oauth_access_grant)

      expect { grant.revoke! }.to change(grant, :revoked?).from(false).to(true)
    end
  end

  describe '#verify_code_challenge' do
    let(:verifier) { 'test_verifier' }
    let(:challenge) { Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false) }
    let(:grant) { create(:administrate_mcp_oauth_access_grant, code_challenge: challenge) }

    it 'accepts the matching verifier and rejects any other' do
      expect(grant.verify_code_challenge(verifier)).to be(true)
      expect(grant.verify_code_challenge('wrong_verifier')).to be(false)
    end
  end

  describe '#reload' do
    it 'drops the plaintext so it lives only on the instance that issued it' do
      grant = create(:administrate_mcp_oauth_access_grant)

      expect { grant.reload }.to change(grant, :plaintext_token).to(nil)
    end
  end
end
