# frozen_string_literal: true

module Administrate
  module MCP
    # Short-lived authorization code for the MCP OAuth 2.1 flow (10-minute TTL).
    class OAuthAccessGrant < ApplicationRecord
      self.table_name = 'administrate_mcp_oauth_access_grants'

      DEFAULT_EXPIRES_IN = 10.minutes.to_i

      belongs_to_admin
      belongs_to :application, class_name: 'Administrate::MCP::OAuthApplication', inverse_of: :access_grants

      validates :token_digest, presence: true, uniqueness: true
      validates :redirect_uri, presence: true
      validates :code_challenge, presence: true
      validates :expires_in, presence: true

      attr_reader :plaintext_token

      class << self
        def generate_token
          SecureRandom.hex(32)
        end

        def digest(plaintext)
          Digest::SHA256.hexdigest(plaintext)
        end

        def find_by_token(plaintext)
          find_by(token_digest: digest(plaintext))
        end

        def issue(
          admin:, application:, redirect_uri:, code_challenge:, code_challenge_method:, scopes:,
          expires_in: DEFAULT_EXPIRES_IN
        )
          plaintext_token = generate_token

          create!(
            admin:,
            application:,
            token_digest: digest(plaintext_token),
            redirect_uri:,
            code_challenge:,
            code_challenge_method:,
            scopes:,
            expires_in:
          ).tap { |grant| grant.instance_variable_set(:@plaintext_token, plaintext_token) }
        end
      end

      def reload(...)
        @plaintext_token = nil
        super
      end

      def expired?
        created_at + expires_in.seconds < Time.current
      end

      def revoked?
        revoked_at.present?
      end

      def revoke!
        update!(revoked_at: Time.current)
      end

      def verify_code_challenge(verifier)
        digest = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
        ActiveSupport::SecurityUtils.secure_compare(digest, code_challenge)
      end
    end
  end
end
