# frozen_string_literal: true

module Administrate
  module MCP
    # Bearer token for authenticating an admin to the MCP server.
    class ApiKey < ApplicationRecord
      self.table_name = 'administrate_mcp_api_keys'

      TOKEN_LENGTH = 40
      WRITE_SCOPE = 'write'

      belongs_to_admin

      has_many :feedbacks, class_name: 'Administrate::MCP::Feedback', dependent: :nullify, inverse_of: :api_key

      validates :token_digest, presence: true, uniqueness: true
      validates :token_prefix, presence: true
      validates :name, presence: true

      scope :active, -> { where(revoked_at: nil) }

      class << self
        def token_prefix_value
          Administrate::MCP.config.api_key_token_prefix
        end

        def generate_token
          "#{token_prefix_value}#{SecureRandom.hex(TOKEN_LENGTH / 2)}"
        end

        def digest_token(plaintext)
          Digest::SHA256.hexdigest(plaintext)
        end

        def authenticate(plaintext)
          return nil unless plaintext&.start_with?(token_prefix_value)

          key = active.find_by(token_digest: digest_token(plaintext))
          return nil unless key

          key.touch(:last_used_at) # rubocop:disable Rails/SkipsModelValidations
          key
        end
      end

      def scopes
        write_access? ? [WRITE_SCOPE] : []
      end

      def revoke!
        update!(revoked_at: Time.current)
      end

      def revoked?
        revoked_at.present?
      end
    end
  end
end
