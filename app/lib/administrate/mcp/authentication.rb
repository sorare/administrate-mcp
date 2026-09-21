# frozen_string_literal: true

module Administrate
  module MCP
    # Extracts and verifies the credentials on an MCP request. Session cookies are never consulted:
    # hosts commonly share a session across sibling subdomains, and the protocol endpoint must not
    # inherit that trust.
    #
    # A bearer token this server issued takes precedence: API keys and the engine's own OAuth tokens
    # are resolved, and a failure on either raises rather than falling through. Anything else — an
    # absent header, or a token no row matches — is offered to `config.identity_fallback`, which is
    # how a host authenticates callers whose token was already resolved in front of the application.
    module Authentication
      OAUTH_ERROR_CODE = -32_001
      API_KEY_ERROR_CODE = -32_001
      MISSING_TOKEN_ERROR_CODE = -32_001
      INACTIVE_ADMIN_ERROR_CODE = -32_001
      EXTERNAL_IDENTITY_ERROR_CODE = -32_001

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

      # Raised by an identity fallback that recognised the caller but found no admin account for
      # them. The host picks the `auth_error_type` the client sees.
      class ExternalIdentityError < Error
        def initialize(message = nil, auth_error_type: 'external')
          super(message)
          @auth_error_type = auth_error_type
        end

        attr_reader :auth_error_type

        def jsonrpc_error_code
          EXTERNAL_IDENTITY_ERROR_CODE
        end
      end

      class << self
        def authenticate!(request)
          token = extract_bearer_token(request)

          if token.present?
            return active!(authenticate_api_key!(token)) if token.start_with?(ApiKey.token_prefix_value)

            oauth_token = find_oauth_token(token)
            return active!(authenticate_oauth_token!(oauth_token)) if oauth_token
          end

          fallback = Administrate::MCP.config.identity_fallback.call(request)
          raise missing_credential_error(token) unless fallback

          active!(fallback)
        end

        private

        # With the OAuth server off the table may not even exist, so it is never queried and an
        # OAuth token is just another bearer the engine does not recognise.
        def find_oauth_token(token)
          return nil unless Administrate::MCP.config.oauth

          OAuthAccessToken.find_by_token(token)
        end

        def authenticate_api_key!(token)
          api_key = ApiKey.authenticate(token)
          raise InvalidApiKeyError, 'Invalid or revoked API key' if api_key.nil?

          Identity.new(admin: api_key.admin, scopes: api_key.scopes)
        end

        def missing_credential_error(token)
          return Error.new('Missing Authorization header') if token.blank?

          OAuthTokenError.new('Invalid token')
        end

        def active!(identity)
          return identity if Administrate::MCP.config.admin_active.call(identity.admin)

          raise InactiveAdminError, 'Admin is no longer active'
        end

        def authenticate_oauth_token!(oauth_token)
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
