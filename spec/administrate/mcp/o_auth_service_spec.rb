# frozen_string_literal: true

RSpec.describe Administrate::MCP::OAuthService do
  subject(:service) { described_class.new }

  describe '#valid_redirect_uri?' do
    let(:application) do
      build(:administrate_mcp_oauth_application, redirect_uris: ['https://client.example.com/callback'])
    end

    it 'accepts an exact match of a registered redirect_uri' do
      expect(service.valid_redirect_uri?(application, 'https://client.example.com/callback')).to be(true)
    end

    it 'rejects an unregistered https redirect_uri' do
      expect(service.valid_redirect_uri?(application, 'https://evil.com/callback')).to be(false)
    end

    it 'rejects a blank redirect_uri' do
      expect(service.valid_redirect_uri?(application, '')).to be(false)
    end

    context 'with loopback redirect_uris' do
      it 'accepts http localhost on any port' do
        expect(service.valid_redirect_uri?(application, 'http://localhost:54321/callback')).to be(true)
      end

      it 'accepts http 127.0.0.1 on any port' do
        expect(service.valid_redirect_uri?(application, 'http://127.0.0.1:8080/cb')).to be(true)
      end

      it 'accepts a .localhost subdomain' do
        expect(service.valid_redirect_uri?(application, 'http://scenic-cedar.localhost:5003/callback')).to be(true)
      end

      it 'rejects a host that merely starts with localhost' do
        expect(service.valid_redirect_uri?(application, 'http://localhost.attacker.com/callback')).to be(false)
      end

      it 'rejects a host that merely starts with 127.0.0.1' do
        expect(service.valid_redirect_uri?(application, 'http://127.0.0.1.attacker.com/callback')).to be(false)
      end

      it 'rejects localhost placed in the userinfo of an attacker host' do
        expect(service.valid_redirect_uri?(application, 'http://localhost@attacker.com/callback')).to be(false)
      end

      it 'rejects https for a loopback host that is not registered' do
        expect(service.valid_redirect_uri?(application, 'https://localhost:3000/callback')).to be(false)
      end

      it 'rejects a malformed uri' do
        expect(service.valid_redirect_uri?(application, 'http://local host/callback')).to be(false)
      end

      context 'when localhost redirects are disabled' do
        before { Administrate::MCP.config.allow_localhost_redirects = false }

        it 'rejects http localhost' do
          expect(service.valid_redirect_uri?(application, 'http://localhost:54321/callback')).to be(false)
        end
      end
    end
  end

  describe '#validate_authorize_params' do
    let(:application) { create(:administrate_mcp_oauth_application) }
    let(:challenge) { Base64.urlsafe_encode64(Digest::SHA256.digest('verifier'), padding: false) }

    def validate(overrides = {})
      service.validate_authorize_params(
        application:,
        redirect_uri: application.redirect_uris.first,
        code_challenge_method: 'S256',
        code_challenge: challenge, **overrides
      )
    end

    it 'accepts a well-formed request' do
      expect(validate).to be_nil
    end

    it 'rejects an unknown client' do
      expect(validate(application: nil)).to eq('Unknown client_id')
    end

    it 'rejects a non-S256 challenge method' do
      expect(validate(code_challenge_method: 'plain')).to eq('Unsupported code_challenge_method, must be S256')
    end

    it 'rejects a malformed challenge' do
      expect(validate(code_challenge: 'tooshort')).to eq('Invalid code_challenge format')
    end
  end
end
