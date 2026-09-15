# frozen_string_literal: true

module Administrate
  module MCP
    # OAuth 2.1 client application registered via Dynamic Client Registration.
    class OAuthApplication < ApplicationRecord
      self.table_name = 'administrate_mcp_oauth_applications'

      MAX_REDIRECT_URIS = 5

      has_many :access_grants,
               class_name: 'Administrate::MCP::OAuthAccessGrant',
               foreign_key: :application_id,
               dependent: :destroy,
               inverse_of: :application
      has_many :access_tokens,
               class_name: 'Administrate::MCP::OAuthAccessToken',
               foreign_key: :application_id,
               dependent: :destroy,
               inverse_of: :application

      validates :client_id, presence: true, uniqueness: true
      validates :name, presence: true, length: { maximum: 255 }
      validates :redirect_uris, presence: true
      validate :validate_redirect_uris

      before_validation :sanitize_name

      def self.generate_client_id
        SecureRandom.hex(16)
      end

      private

      def sanitize_name
        self.name = ActionController::Base.helpers.strip_tags(name)&.strip if name.present?
      end

      def validate_redirect_uris
        return if redirect_uris.blank?

        if redirect_uris.length > MAX_REDIRECT_URIS
          errors.add(:redirect_uris, "must not exceed #{MAX_REDIRECT_URIS} URIs")
          return
        end

        redirect_uris.each { |uri_string| validate_single_redirect_uri(uri_string) }
      end

      def validate_single_redirect_uri(uri_string)
        uri = URI.parse(uri_string)
        return if uri.scheme == 'http' && loopback_allowed?(uri.host)

        errors.add(:redirect_uris, "#{uri_string} must use https scheme") unless uri.scheme == 'https'
      rescue URI::InvalidURIError
        errors.add(:redirect_uris, "#{uri_string} is not a valid URI")
      end

      def loopback_allowed?(host)
        Administrate::MCP.config.allow_localhost_redirects && LoopbackUri.localhost?(host)
      end
    end
  end
end
