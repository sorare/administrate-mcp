# frozen_string_literal: true

module Administrate
  module MCP
    # Short-lived authorization code for the MCP OAuth 2.1 flow (10-minute TTL).
    class OAuthAccessGrant < ApplicationRecord
      self.table_name = 'administrate_mcp_oauth_access_grants'

      DEFAULT_EXPIRES_IN = 10.minutes.to_i

      belongs_to_admin
      belongs_to :application, class_name: 'Administrate::MCP::OAuthApplication', inverse_of: :access_grants

      validates :token, presence: true, uniqueness: true
      validates :redirect_uri, presence: true
      validates :code_challenge, presence: true
      validates :expires_in, presence: true

      def self.generate_token
        SecureRandom.hex(32)
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
