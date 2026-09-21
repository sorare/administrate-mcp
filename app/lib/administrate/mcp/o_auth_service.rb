# frozen_string_literal: true

module Administrate
  module MCP
    # OAuth 2.1 service for MCP authentication: parameter validation and token exchange.
    # Implements RFC 9126 (PAR), RFC 7636 (PKCE), and RFC 6749 (OAuth 2.0) token exchange.
    # See https://datatracker.ietf.org/doc/html/draft-ietf-oauth-v2-1-12
    class OAuthService
      BASE64URL_CHALLENGE_PATTERN = /\A[A-Za-z0-9_-]{43,128}\z/

      Result = Struct.new(:success?, :data, :error, :error_description, keyword_init: true)

      def validate_authorize_params(application:, redirect_uri:, code_challenge_method:, code_challenge:)
        return 'Unknown client_id' unless application
        return 'Invalid redirect_uri' unless valid_redirect_uri?(application, redirect_uri)
        unless supported_challenge_method?(code_challenge_method)
          return 'Unsupported code_challenge_method, must be S256'
        end
        return 'Invalid code_challenge format' unless valid_code_challenge?(code_challenge)

        nil
      end

      def valid_redirect_uri?(application, uri)
        return false if uri.blank?
        return true if application.redirect_uris.include?(uri)

        loopback_redirect_uri?(uri)
      end

      def exchange_authorization_code(code:, code_verifier:, redirect_uri:)
        grant = find_valid_grant(code)
        return error_result('invalid_grant') unless grant
        return error_result('invalid_grant', 'redirect_uri mismatch') if redirect_uri_mismatch?(grant, redirect_uri)
        unless grant.verify_code_challenge(code_verifier.to_s)
          return error_result('invalid_grant', 'PKCE verification failed')
        end

        grant.revoke!
        success_result(issue_access_token(grant.admin, grant.application, grant.scopes))
      end

      def exchange_refresh_token(refresh_token:)
        old_token = OAuthAccessToken.active.find_by_refresh_token(refresh_token)
        return error_result('invalid_grant') unless old_token && !old_token.expired?

        old_token.revoke!
        success_result(issue_access_token(old_token.admin, old_token.application, old_token.scopes))
      end

      private

      # Loopback redirects (RFC 8252) are allowed on any port, but the host must be a real loopback
      # host — matched on the parsed hostname, so `http://localhost.attacker.com` cannot intercept an
      # authorization code.
      def loopback_redirect_uri?(uri)
        return false unless Administrate::MCP.config.allow_localhost_redirects

        parsed = URI.parse(uri)
        parsed.scheme == 'http' && LoopbackUri.localhost?(parsed.hostname)
      rescue URI::InvalidURIError
        false
      end

      def valid_code_challenge?(challenge)
        challenge.blank? || BASE64URL_CHALLENGE_PATTERN.match?(challenge)
      end

      def supported_challenge_method?(method)
        method.blank? || method == 'S256'
      end

      def find_valid_grant(code)
        grant = OAuthAccessGrant.find_by_token(code)
        grant if grant && !grant.revoked? && !grant.expired?
      end

      def redirect_uri_mismatch?(grant, redirect_uri)
        redirect_uri.present? && grant.redirect_uri != redirect_uri
      end

      def issue_access_token(admin, application, scopes)
        OAuthAccessToken.issue(admin:, application:, scopes:, expires_in: OAuthAccessToken::DEFAULT_EXPIRES_IN)
      end

      def success_result(access_token)
        Result.new(
          success?: true,
          data: {
            access_token: access_token.plaintext_token,
            token_type: 'bearer',
            expires_in: access_token.expires_in,
            refresh_token: access_token.plaintext_refresh_token
          }
        )
      end

      def error_result(error, description = nil)
        Result.new(success?: false, error:, error_description: description)
      end
    end
  end
end
