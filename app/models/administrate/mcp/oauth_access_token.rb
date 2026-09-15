# frozen_string_literal: true

module Administrate
  module MCP
    # MCP OAuth 2.1 access token (1-week TTL).
    class OAuthAccessToken < ApplicationRecord
      self.table_name = 'administrate_mcp_oauth_access_tokens'

      DEFAULT_EXPIRES_IN = 1.week.to_i

      belongs_to_admin
      belongs_to :application, class_name: 'Administrate::MCP::OAuthApplication', inverse_of: :access_tokens

      validates :token, presence: true, uniqueness: true
      validates :refresh_token, presence: true, uniqueness: true
      validates :expires_in, presence: true

      scope :active, -> { where(revoked_at: nil) }

      def self.generate_token
        SecureRandom.hex(32)
      end

      def self.generate_refresh_token
        SecureRandom.hex(32)
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
