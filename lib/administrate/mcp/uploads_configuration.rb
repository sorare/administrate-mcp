# frozen_string_literal: true

module Administrate
  module MCP
    # Settings for presigned uploads: the `uploads_prepare` tool and the `<attribute>_upload_id`
    # params of actions declared with `uploads:`. Off until the host enables it, because it needs
    # the upload batches table. `allowed_content_types` and `max_size` are defaults an action can
    # override per attribute.
    class UploadsConfiguration
      CONTENT_TYPES = {
        '.png' => 'image/png',
        '.jpg' => 'image/jpeg',
        '.jpeg' => 'image/jpeg',
        '.webp' => 'image/webp'
      }.freeze

      Rules =
        Data.define(:content_types, :max_size) do
          def content_type_for(filename)
            content_types[File.extname(filename.to_s).downcase]
          end

          def allowed_content_type?(content_type)
            content_types.value?(content_type)
          end
        end

      attr_accessor :enabled, :allowed_content_types, :max_size, :max_files, :url_ttl, :batch_ttl
      attr_writer :storage

      def initialize
        @enabled = false
        @storage = nil
        @allowed_content_types = CONTENT_TYPES.dup
        @max_size = 10 * 1024 * 1024
        @max_files = 10
        @url_ttl = 15 * 60
        @batch_ttl = 60 * 60
      end

      def storage
        @storage || default_storage
      end

      def rules(content_types: nil, max_size: nil)
        Rules.new(content_types: (content_types || allowed_content_types).transform_keys(&:to_s),
                  max_size: max_size || self.max_size)
      end

      private

      def default_storage
        if defined?(::Shrine)
          Uploads::ShrineStorage.new
        elsif defined?(::ActiveStorage::Blob)
          Uploads::ActiveStorageStorage.new
        end
      end
    end
  end
end
