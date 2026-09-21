# frozen_string_literal: true

module Administrate
  module MCP
    # MCP OAuth 2.1 access token (1-week TTL).
    class OAuthAccessToken < ApplicationRecord
      self.table_name = 'administrate_mcp_oauth_access_tokens'

      DEFAULT_EXPIRES_IN = 1.week.to_i

      belongs_to_admin
      belongs_to :application, class_name: 'Administrate::MCP::OAuthApplication', inverse_of: :access_tokens

      validates :token_digest, presence: true, uniqueness: true
      validates :refresh_token_digest, presence: true, uniqueness: true
      validates :expires_in, presence: true

      scope :active, -> { where(revoked_at: nil) }

      attr_reader :plaintext_token, :plaintext_refresh_token

      class << self
        def generate_token
          SecureRandom.hex(32)
        end

        def generate_refresh_token
          SecureRandom.hex(32)
        end

        def digest(plaintext)
          Digest::SHA256.hexdigest(plaintext)
        end

        def find_by_token(plaintext)
          find_by(token_digest: digest(plaintext))
        end

        def find_by_refresh_token(plaintext)
          find_by(refresh_token_digest: digest(plaintext))
        end

        def issue(admin:, application:, scopes:, expires_in: DEFAULT_EXPIRES_IN)
          plaintext_token = generate_token
          plaintext_refresh_token = generate_refresh_token

          create!(
            admin:,
            application:,
            token_digest: digest(plaintext_token),
            refresh_token_digest: digest(plaintext_refresh_token),
            expires_in:,
            scopes:
          ).tap do |token|
            token.instance_variable_set(:@plaintext_token, plaintext_token)
            token.instance_variable_set(:@plaintext_refresh_token, plaintext_refresh_token)
          end
        end
      end

      def reload(...)
        @plaintext_token = nil
        @plaintext_refresh_token = nil
        super
      end

      def expired?
        created_at + expires_in.seconds < Time.current
      end

      def revoked?
        revoked_at.present?
      end

      def accessible?
        !revoked? && !expired?
      end

      def revoke!
        update!(revoked_at: Time.current)
      end
    end
  end
end
