# frozen_string_literal: true

RSpec.describe Administrate::MCP::OAuthAccessToken do
  describe 'validations' do
    subject { create(:administrate_mcp_oauth_access_token) }

    it do
      is_expected.to belong_to(:admin)
      is_expected.to belong_to(:application).class_name('Administrate::MCP::OAuthApplication')
      is_expected.to validate_presence_of(:token)
      is_expected.to validate_uniqueness_of(:token)
      is_expected.to validate_presence_of(:refresh_token)
      is_expected.to validate_uniqueness_of(:refresh_token)
      is_expected.to validate_presence_of(:expires_in)
    end
  end

  describe '.generate_token' do
    it 'generates 64-character hex strings' do
      expect(described_class.generate_token).to match(/\A[0-9a-f]{64}\z/)
      expect(described_class.generate_refresh_token).to match(/\A[0-9a-f]{64}\z/)
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
end
