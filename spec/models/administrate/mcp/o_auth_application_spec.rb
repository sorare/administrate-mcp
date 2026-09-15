# frozen_string_literal: true

RSpec.describe Administrate::MCP::OAuthApplication do
  describe 'validations' do
    subject { create(:administrate_mcp_oauth_application) }

    it do
      is_expected.to validate_presence_of(:client_id)
      is_expected.to validate_uniqueness_of(:client_id)
      is_expected.to validate_presence_of(:name)
      is_expected.to validate_presence_of(:redirect_uris)
    end
  end

  describe '.generate_client_id' do
    it 'generates a 32-character hex string' do
      expect(described_class.generate_client_id).to match(/\A[0-9a-f]{32}\z/)
    end
  end

  describe 'redirect_uris' do
    def application(uris)
      build(:administrate_mcp_oauth_application, redirect_uris: uris)
    end

    it 'accepts https' do
      expect(application(['https://example.com/cb'])).to be_valid
    end

    it 'accepts http on a loopback host' do
      expect(application(['http://localhost:3000/cb'])).to be_valid
      expect(application(['http://127.0.0.1:3000/cb'])).to be_valid
    end

    it 'accepts http on the IPv6 loopback' do
      expect(application(['http://[::1]:8080/cb'])).to be_valid
    end

    it 'rejects http elsewhere' do
      expect(application(['http://evil.com/cb'])).not_to be_valid
    end

    it 'rejects a malformed uri' do
      expect(application(['not a valid uri %%%'])).not_to be_valid
    end

    it 'rejects more than the maximum' do
      expect(application(Array.new(6) { |i| "https://example.com/cb#{i}" })).not_to be_valid
    end

    context 'when localhost redirects are disabled' do
      before { Administrate::MCP.config.allow_localhost_redirects = false }

      it 'rejects http on a loopback host' do
        expect(application(['http://localhost:3000/cb'])).not_to be_valid
      end
    end
  end

  describe 'name sanitization' do
    it 'strips HTML tags' do
      application = create(:administrate_mcp_oauth_application, name: '<script>alert("xss")</script>Evil Client')

      expect(application.name).to eq('alert("xss")Evil Client')
    end
  end
end
