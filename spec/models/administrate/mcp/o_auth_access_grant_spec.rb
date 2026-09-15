# frozen_string_literal: true

RSpec.describe Administrate::MCP::OAuthAccessGrant do
  describe 'validations' do
    subject { create(:administrate_mcp_oauth_access_grant) }

    it do
      is_expected.to belong_to(:admin)
      is_expected.to belong_to(:application).class_name('Administrate::MCP::OAuthApplication')
      is_expected.to validate_presence_of(:token)
      is_expected.to validate_uniqueness_of(:token)
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
end
