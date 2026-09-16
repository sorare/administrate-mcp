# frozen_string_literal: true

require 'jwt'
require 'net/http'

module Administrate
  module MCP
    # Verifies the signed assertion Cloudflare Access attaches to every request it lets through.
    #
    # Clients using Access managed OAuth never reach an MCP server's own OAuth flow: Access resolves
    # their token at its own edge and forwards the caller's identity in this header instead. Build
    # one of these and hand it to `config.identity_fallback` — it answers `call(request)`.
    class CloudflareAccess
      ASSERTION_HEADER = 'Cf-Access-Jwt-Assertion'
      ALGORITHM = 'RS256'
      CERTS_PATH = '/cdn-cgi/access/certs'
      KEYS_CACHE_EXPIRY = 1.hour
      AUTH_ERROR_TYPE = 'cloudflare_access'

      NETWORK_ERRORS = [
        Errno::ECONNREFUSED,
        Errno::ECONNRESET,
        Errno::EHOSTUNREACH,
        Errno::ENETUNREACH,
        IOError,
        Net::OpenTimeout,
        Net::ReadTimeout,
        OpenSSL::SSL::SSLError,
        SocketError,
        Timeout::Error
      ].freeze

      # `team_domain` and `audience` each take a value or something that answers `call`. Hosts build
      # this in an initializer, before the environment that carries those settings is necessarily
      # readable, so a callable is re-read on every request rather than captured at boot.
      def initialize(team_domain:, audience:, find_admin:, scopes_for: ->(_admin) { [] })
        @team_domain = team_domain
        @audience = audience
        @find_admin = find_admin
        @scopes_for = scopes_for
      end

      def team_domain
        resolve(@team_domain)
      end

      def audience
        resolve(@audience)
      end

      def call(request)
        return nil unless configured?

        assertion = request.headers[ASSERTION_HEADER]
        return nil if assertion.blank?

        payload = verify(assertion)
        return nil if payload.nil?

        admin = find_admin!(payload['email'])
        Authentication::Identity.new(admin:, scopes: @scopes_for.call(admin))
      end

      def configured?
        team_domain.present? && audience.present?
      end

      def verify(assertion)
        kid = key_id(assertion)
        return nil if kid.blank?

        key = find_key(kid) || find_key(kid, refresh: true)
        return nil if key.nil?

        decode(assertion, key)
      end

      def decode(assertion, key)
        JWT.decode(
          assertion,
          JWT::JWK.import(key).public_key,
          true,
          algorithms: [ALGORITHM],
          iss: team_domain,
          verify_iss: true,
          aud: audience,
          verify_aud: true
        ).first
      rescue JWT::DecodeError, JWT::JWKError
        nil
      end

      def key_id(assertion)
        JSON.parse(Base64.urlsafe_decode64(assertion.split('.').first))['kid']
      rescue ArgumentError, JSON::ParserError
        nil
      end

      def find_key(kid, refresh: false)
        Rails.cache.delete(certs_url) if refresh
        keys = Rails.cache.fetch(certs_url, expires_in: KEYS_CACHE_EXPIRY, skip_nil: true) { fetch_keys }
        keys&.find { |key| key['kid'] == kid }
      end

      def fetch_keys
        JSON.parse(Net::HTTP.get(URI.parse(certs_url)))['keys']
      rescue JSON::ParserError, *NETWORK_ERRORS
        nil
      end

      def certs_url
        "#{team_domain}#{CERTS_PATH}"
      end

      private

      def resolve(setting)
        value = setting.respond_to?(:call) ? setting.call : setting
        value.presence
      end

      # The identity provider decides how it capitalises an address; the lookup should not care.
      def find_admin!(email)
        admin = @find_admin.call(email.to_s.downcase)
        return admin if admin

        raise Authentication::ExternalIdentityError.new(
          "No admin account for #{email}",
          auth_error_type: AUTH_ERROR_TYPE
        )
      end
    end
  end
end
