# frozen_string_literal: true

module Administrate
  module MCP
    # The files an admin was handed presigned upload URLs for. Each entry of `files` holds the
    # upload_id given to the client, the storage key, and the declared filename, content type and
    # size.
    class UploadBatch < ApplicationRecord
      self.table_name = 'administrate_mcp_upload_batches'

      belongs_to_admin

      scope :with_upload, ->(upload_id) { where('files @> ?', [{ upload_id: }].to_json) }

      def expired?
        expires_at <= Time.current
      end

      def file(upload_id)
        files.find { |entry| entry['upload_id'] == upload_id }
      end
    end
  end
end
