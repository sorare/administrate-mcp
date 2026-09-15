# frozen_string_literal: true

RSpec.describe Administrate::MCP::Configuration do
  subject(:config) { described_class.new }

  describe '#api_key_token_prefix=' do
    it 'accepts a prefix' do
      config.api_key_token_prefix = 'smcp_'

      expect(config.api_key_token_prefix).to eq('smcp_')
    end

    it 'refuses a blank prefix, which would swallow every OAuth token' do
      expect { config.api_key_token_prefix = '' }.to raise_error(ArgumentError, /cannot be blank/)
      expect { config.api_key_token_prefix = nil }.to raise_error(ArgumentError, /cannot be blank/)
      expect(config.api_key_token_prefix).to eq('amcp_')
    end
  end

  describe '#issuer_for' do
    it 'returns a plain string unchanged' do
      config.issuer = 'https://admin-mcp.example.com'

      expect(config.issuer_for).to eq('https://admin-mcp.example.com')
    end

    it 'calls a proc with the request' do
      config.issuer = ->(request) { "https://#{request}.example.com" }

      expect(config.issuer_for('mcp')).to eq('https://mcp.example.com')
    end
  end
end
