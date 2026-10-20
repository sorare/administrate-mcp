# frozen_string_literal: true

module Administrate
  module MCP
    module Uploads
      # The default upload storage: presigns a PUT on a Shrine storage (`:cache` by default) and
      # reads the uploaded object back with the uploader's own metadata extraction, so the
      # host's `determine_mime_type` and `store_dimensions` plugins apply. The resolved value is the
      # cached file's data hash, which any attachment of that uploader accepts without a copy.
      class ShrineStorage
        Upload = Data.define(:mime_type, :size, :value)

        def initialize(uploader: 'Shrine', storage_key: :cache)
          @uploader = uploader
          @storage_key = storage_key.to_sym
        end

        def presignable?
          storage.respond_to?(:presign)
        end

        def description
          "Shrine storage :#{@storage_key} (#{storage.class.name})"
        end

        def presign(key, content_type:, expires_in:)
          presigned = storage.presign(key, method: :put, expires_in:, content_type:)
          { url: presigned[:url], headers: presigned[:headers] || {} }
        end

        def fetch(key, filename:)
          file = uploader_class.uploaded_file('storage' => @storage_key.to_s, 'id' => key,
                                              'metadata' => { 'filename' => filename })
          return unless file.exists?

          extracted = file.open { uploader_class.new(@storage_key).extract_metadata(file) }
          metadata = file.metadata.merge(extracted.compact, 'filename' => filename)
          Upload.new(mime_type: metadata['mime_type'], size: metadata['size'],
                     value: file.data.merge('metadata' => metadata))
        end

        private

        def uploader_class
          @uploader.is_a?(Class) ? @uploader : @uploader.to_s.constantize
        end

        def storage
          uploader_class.storages.fetch(@storage_key)
        end
      end
    end
  end
end
