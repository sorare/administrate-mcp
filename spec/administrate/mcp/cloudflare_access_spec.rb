# frozen_string_literal: true

require 'webmock/rspec'

RSpec.describe Administrate::MCP::CloudflareAccess do
  subject(:access) { described_class.new(team_domain:, audience:, find_admin:, **scopes) }

  let(:admin) { create(:admin) }
  let(:team_domain) { 'https://example.cloudflareaccess.com' }
  let(:audience) { '9b1e4f0c3a' }
  let(:certs_url) { "#{team_domain}/cdn-cgi/access/certs" }
  let(:rsa_key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:jwk) { JWT::JWK.new(rsa_key) }
  let(:assertion) { sign }
  let(:find_admin) { ->(email) { Admin.find_by(email:) } }
  let(:scopes) { {} }

  def sign(key: rsa_key, kid: jwk.kid, **claims)
    payload = { iss: team_domain, aud: audience, email: admin.email, exp: 1.hour.from_now.to_i }.merge(claims)

    JWT.encode(payload, key, 'RS256', { kid: })
  end

  def request_with(value)
    instance_double(ActionDispatch::Request, headers: { described_class::ASSERTION_HEADER => value })
  end

  def stub_certs(*key_sets)
    responses = key_sets.map { |keys| { body: { keys: }.to_json, headers: { 'Content-Type' => 'application/json' } } }
    WebMock.stub_request(:get, certs_url).to_return(*responses)
  end

  before { Rails.cache.delete(certs_url) }

  describe '#call' do
    context 'with a valid assertion' do
      before { stub_certs([jwk.export]) }

      it 'returns the admin with no scopes by default' do
        identity = access.call(request_with(assertion))

        expect(identity.admin).to eq(admin)
        expect(identity.scopes).to eq([])
      end

      context 'with an injected scopes_for' do
        let(:scopes) { { scopes_for: ->(resolved) { resolved.role == 'full_access' ? ['write'] : [] } } }
        let(:admin) { create(:admin, :full_access) }

        it 'returns the scopes it decides on' do
          expect(access.call(request_with(assertion)).scopes).to eq(['write'])
        end
      end

      context 'when the identity provider capitalises the email' do
        let(:assertion) { sign(email: admin.email.upcase) }

        it 'still resolves the admin' do
          expect(access.call(request_with(assertion)).admin).to eq(admin)
        end
      end

      context 'with an injected find_admin' do
        let(:other) { create(:admin) }
        let(:find_admin) { ->(_email) { other } }

        it 'uses whatever the host looks up' do
          expect(access.call(request_with(assertion)).admin).to eq(other)
        end
      end

      context 'when no admin has that email' do
        let(:assertion) { sign(email: 'someone.else@example.com') }

        it 'raises an ExternalIdentityError carrying the cloudflare_access error type' do
          expect { access.call(request_with(assertion)) }.to raise_error(
            Administrate::MCP::Authentication::ExternalIdentityError,
            'No admin account for someone.else@example.com'
          ) { |error| expect(error.auth_error_type).to eq('cloudflare_access') }
        end
      end
    end

    context 'when Access signing keys have rotated' do
      let(:previous_key) { JWT::JWK.new(OpenSSL::PKey::RSA.generate(2048)) }

      before { stub_certs([previous_key.export], [jwk.export]) }

      it 'refetches the key set once and accepts the assertion' do
        expect(access.call(request_with(assertion)).admin).to eq(admin)
      end
    end

    context 'with an assertion signed by an unknown key' do
      let(:assertion) { sign(key: OpenSSL::PKey::RSA.generate(2048), kid: 'unknown-kid') }

      before { stub_certs([jwk.export], [jwk.export]) }

      it 'returns nil' do
        expect(access.call(request_with(assertion))).to be_nil
      end
    end

    context 'with an assertion for another audience' do
      let(:assertion) { sign(aud: 'another-application') }

      before { stub_certs([jwk.export]) }

      it 'returns nil' do
        expect(access.call(request_with(assertion))).to be_nil
      end
    end

    context 'with an assertion from another team domain' do
      let(:assertion) { sign(iss: 'https://attacker.cloudflareaccess.com') }

      before { stub_certs([jwk.export]) }

      it 'returns nil' do
        expect(access.call(request_with(assertion))).to be_nil
      end
    end

    context 'with an expired assertion' do
      let(:assertion) { sign(exp: 1.hour.ago.to_i) }

      before { stub_certs([jwk.export]) }

      it 'returns nil' do
        expect(access.call(request_with(assertion))).to be_nil
      end
    end

    context 'with a malformed assertion' do
      it 'returns nil' do
        expect(access.call(request_with('not-a-jwt'))).to be_nil
      end
    end

    context 'with no assertion header' do
      it 'returns nil' do
        expect(access.call(request_with(nil))).to be_nil
      end
    end

    context 'when the certs endpoint is unreachable' do
      before { WebMock.stub_request(:get, certs_url).to_timeout }

      it 'returns nil rather than raising' do
        expect(access.call(request_with(assertion))).to be_nil
      end
    end

    context 'when it is not configured' do
      let(:team_domain) { '' }
      let(:audience) { '' }

      it 'returns nil without calling Cloudflare' do
        expect(access.call(request_with('anything'))).to be_nil
        expect(WebMock).not_to have_requested(:get, certs_url)
      end
    end
  end

  describe 'settings supplied as a callable' do
    subject(:access) do
      described_class.new(
        team_domain: -> { configured_team_domain },
        audience: -> { configured_audience },
        find_admin:
      )
    end

    let(:configured_team_domain) { nil }
    let(:configured_audience) { nil }

    before { stub_certs([jwk.export]) }

    context 'when neither is readable yet, as at boot' do
      it 'refuses the assertion without calling Cloudflare' do
        expect(access.call(request_with(assertion))).to be_nil
        expect(WebMock).not_to have_requested(:get, certs_url)
      end
    end

    context 'when the team domain arrives after construction' do
      let(:configured_audience) { audience }

      it 'is refused while blank and accepted once it reads' do
        expect(access.call(request_with(assertion))).to be_nil

        allow(self).to receive(:configured_team_domain).and_return(team_domain)

        expect(access.call(request_with(assertion)).admin).to eq(admin)
      end
    end

    context 'when the audience arrives after construction' do
      let(:configured_team_domain) { team_domain }

      it 'is refused while blank and accepted once it reads' do
        expect(access.call(request_with(assertion))).to be_nil

        allow(self).to receive(:configured_audience).and_return(audience)

        expect(access.call(request_with(assertion)).admin).to eq(admin)
      end
    end

    context 'when the audience is blank but the team domain reads' do
      let(:configured_team_domain) { team_domain }

      it 'accepts nothing rather than skipping the audience check' do
        expect(access.call(request_with(sign(aud: 'any-other-application')))).to be_nil
        expect(access.call(request_with(assertion))).to be_nil
      end
    end
  end

  describe 'as an identity fallback' do
    before do
      stub_certs([jwk.export])
      Administrate::MCP.config.identity_fallback = access
    end

    it 'authenticates a request carrying only the Access assertion' do
      request = instance_double(
        ActionDispatch::Request,
        headers: { described_class::ASSERTION_HEADER => assertion, 'Authorization' => nil }
      )

      expect(Administrate::MCP::Authentication.authenticate!(request).admin).to eq(admin)
    end
  end
end
