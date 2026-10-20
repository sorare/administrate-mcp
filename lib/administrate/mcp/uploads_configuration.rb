# frozen_string_literal: true

module Administrate
  module MCP
    # Settings for presigned uploads: the `uploads_prepare` tool and the `<attribute>_upload_id`
    # params of actions declared with `uploads: true`. Off until the host enables it, because it
    # needs the upload batches table.
    class UploadsConfiguration
      CONTENT_TYPES = {
        '.png' => 'image/png',
        '.jpg' => 'image/jpeg',
        '.jpeg' => 'image/jpeg',
        '.webp' => 'image/webp'
      }.freeze

      attr_accessor :enabled, :allowed_content_types, :max_size, :url_ttl, :batch_ttl
      attr_writer :storage

      def initialize
        @enabled = false
        @storage = nil
        @allowed_content_types = CONTENT_TYPES.dup
        @max_size = 10 * 1024 * 1024
        @url_ttl = 15 * 60
        @batch_ttl = 60 * 60
      end

      def storage
        @storage || (Uploads::ShrineStorage.new if defined?(::Shrine))
      end

      def content_type_for(filename)
        allowed_content_types[File.extname(filename.to_s).downcase]
      end

      def allowed_content_type?(content_type)
        allowed_content_types.value?(content_type)
      end
    end
  end
end
