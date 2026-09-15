# frozen_string_literal: true

module Administrate
  module MCP
    # Extracts and verifies bearer tokens from MCP requests. Session cookies are never consulted:
    # hosts commonly share a session across sibling subdomains, and the protocol endpoint must not
    # inherit that trust.
    module Authentication
      OAUTH_ERROR_CODE = -32_001
      API_KEY_ERROR_CODE = -32_001
      MISSING_TOKEN_ERROR_CODE = -32_001
      INACTIVE_ADMIN_ERROR_CODE = -32_001

      # Authenticated caller: the admin plus the scopes their credential carries. API keys are
      # read-only unless granted write access; OAuth tokens carry the scopes they were granted.
      Identity = Struct.new(:admin, :scopes, keyword_init: true)

      # Base authentication error for MCP requests.
      class Error < StandardError
        def auth_error_type
          'unknown'
        end

        def jsonrpc_error_code
          MISSING_TOKEN_ERROR_CODE
        end
      end

      # Raised when an OAuth access token is invalid, expired, or revoked.
      class OAuthTokenError < Error
        def auth_error_type
          'oauth'
        end

        def jsonrpc_error_code
          OAUTH_ERROR_CODE
        end
      end

      # Raised when an API key is invalid or revoked.
      class InvalidApiKeyError < Error
        def auth_error_type
          'api_key'
        end

        def jsonrpc_error_code
          API_KEY_ERROR_CODE
        end
      end

      # Raised when the credential is still valid but its owner no longer is. A credential outlives
      # the admin who holds it, so the host is asked on every call.
      class InactiveAdminError < Error
        def auth_error_type
          'inactive_admin'
        end

        def jsonrpc_error_code
          INACTIVE_ADMIN_ERROR_CODE
        end
      end

      class << self
        def authenticate!(request)
          token = extract_bearer_token(request)
          raise Error, 'Missing Authorization header' if token.blank?

          if token.start_with?(ApiKey.token_prefix_value)
            api_key = ApiKey.authenticate(token)
            raise InvalidApiKeyError, 'Invalid or revoked API key' if api_key.nil?

            return active!(Identity.new(admin: api_key.admin, scopes: api_key.scopes))
          end

          active!(authenticate_oauth_token!(token))
        end

        private

        def active!(identity)
          return identity if Administrate::MCP.config.admin_active.call(identity.admin)

          raise InactiveAdminError, 'Admin is no longer active'
        end

        def authenticate_oauth_token!(token)
          oauth_token = OAuthAccessToken.find_by(token:)
          raise OAuthTokenError, 'Invalid token' if oauth_token.nil?
          raise OAuthTokenError, 'Token has been revoked' if oauth_token.revoked?
          raise OAuthTokenError, 'Token has expired' if oauth_token.expired?

          Identity.new(admin: oauth_token.admin, scopes: oauth_token.scopes.to_s.split)
        end

        def extract_bearer_token(request)
          header = request.headers['Authorization']
          return nil if header.blank?

          header[/\ABearer (.+)\z/, 1]
        end
      end
    end
  end
end
