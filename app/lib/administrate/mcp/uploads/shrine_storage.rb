# frozen_string_literal: true

module Administrate
  module MCP
    module Uploads
      # The default upload storage, on a Shrine storage (`:cache` by default). It presigns a POST
      # whose policy bounds the content length, so the storage itself refuses a file above the
      # maximum size. Fetching copies the uploaded object to a key no URL points to, so what is
      # checked and attached cannot be replaced afterwards; on S3 the copy happens server side.
      # Metadata comes from the uploader's own extraction, so the host's `determine_mime_type` and
      # `store_dimensions` plugins apply, and runs only once the size is known to be acceptable.
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

        def presign(key, content_type:, max_size:, expires_in:, **)
          presigned = storage.presign(key, method: :post, content_type:, content_length_range: 1..max_size,
                                           signature_expiration: expires_in.seconds.from_now)
          { method: 'POST', url: presigned[:url], fields: presigned[:fields] }
        end

        def fetch(key, filename:, max_size:)
          original = uploaded_file(key, filename)
          return unless original.exists?

          copy = uploader.upload(original, location: "#{SecureRandom.uuid}#{File.extname(key)}")
          copy.open do
            next Upload.new(mime_type: nil, size: copy.size, value: copy.data) if copy.size.to_i > max_size

            describe(copy, filename)
          end
        end

        def delete(value)
          uploader_class.uploaded_file(value).delete
        end

        private

        def describe(file, filename)
          metadata = file.metadata.merge(uploader.extract_metadata(file).compact, 'filename' => filename)
          Upload.new(mime_type: metadata['mime_type'], size: metadata['size'],
                     value: file.data.merge('metadata' => metadata))
        end

        def uploaded_file(key, filename)
          uploader_class.uploaded_file('storage' => @storage_key.to_s, 'id' => key,
                                       'metadata' => { 'filename' => filename })
        end

        def uploader
          uploader_class.new(@storage_key)
        end

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
