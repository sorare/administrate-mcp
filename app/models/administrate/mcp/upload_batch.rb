# frozen_string_literal: true

module Administrate
  module MCP
    # The files an admin was handed presigned upload URLs for. Each entry of `files` holds the
    # upload_id given to the client, the storage key, the declared filename, content type and size,
    # the action tool and attribute it was prepared for, and, once resolved, the checked value.
    class UploadBatch < ApplicationRecord
      self.table_name = 'administrate_mcp_upload_batches'

      belongs_to_admin

      scope :with_upload, ->(upload_id) { where('files @> ?', [{ upload_id: }].to_json) }
      scope :expired, ->(at = Time.current) { where(expires_at: ...at) }

      def expired?
        expires_at <= Time.current
      end

      def file(upload_id)
        files.find { |entry| entry['upload_id'] == upload_id }
      end

      def record_value!(upload_id, value)
        update!(files: files.map { |entry| entry['upload_id'] == upload_id ? entry.merge('value' => value) : entry })
      end
    end
  end
end
