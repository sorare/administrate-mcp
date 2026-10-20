# frozen_string_literal: true

module Administrate
  module MCP
    module Uploads
      # An upload storage on an Active Storage service, through its direct uploads. Preparing a file
      # creates a blob with the declared byte size and MD5 checksum and signs a PUT for exactly
      # them, so the service refuses any other size or content. Fetching copies the uploaded object
      # to a key no URL points to, reads the copy's content type from its first bytes, and hands
      # the action the copy's signed blob id, which an Active Storage attachment accepts. Deleting a
      # value purges its blob; a source above the maximum is described as is, so it is purged too.
      class ActiveStorageStorage
        Upload = Data.define(:mime_type, :size, :value)

        IDENTIFIABLE_BYTES = 4096

        def initialize(service_name: nil, url_options: nil)
          @service_name = service_name&.to_sym
          @url_options = url_options
        end

        def presignable?
          return false unless service.respond_to?(:url_for_direct_upload)

          !service.is_a?(ActiveStorage::Service::DiskService) || url_options.present?
        end

        def checksum_required?
          true
        end

        def description
          "Active Storage service :#{service.name} (#{service.class.name})"
        end

        def presign(key, content_type:, expires_in:, filename:, size:, checksum:, **)
          blob = ActiveStorage::Blob.create_before_direct_upload!(key:, filename:, byte_size: size, checksum:,
                                                                  content_type:, service_name: service.name)
          ActiveStorage::Current.set(url_options:) do
            { method: 'PUT', url: blob.service_url_for_direct_upload(expires_in:),
              headers: blob.service_headers_for_direct_upload }
          end
        end

        def fetch(key, filename:, max_size:)
          source = ActiveStorage::Blob.find_by(key:, service_name: service.name)
          return unless source && service.exist?(key)
          return oversized(source) if source.byte_size > max_size

          copy_key = ActiveStorage::Blob.generate_unique_secure_token
          service.compose([key], copy_key)
          describe(copy(source, copy_key, filename))
        end

        def delete(value)
          ActiveStorage::Blob.find_signed(value)&.purge
        end

        private

        def copy(source, key, filename)
          ActiveStorage::Blob.create!(key:, filename:, byte_size: source.byte_size, checksum: source.checksum,
                                      content_type: identify(key), metadata: { identified: true },
                                      service_name: service.name)
        end

        def identify(key)
          Marcel::MimeType.for(StringIO.new(service.download_chunk(key, 0...IDENTIFIABLE_BYTES)))
        end

        def oversized(blob)
          Upload.new(mime_type: nil, size: blob.byte_size, value: blob.signed_id)
        end

        def describe(blob)
          Upload.new(mime_type: blob.content_type, size: blob.byte_size, value: blob.signed_id)
        end

        def url_options
          @url_options || ActiveStorage::Current.url_options
        end

        def service
          @service_name ? ActiveStorage::Blob.services.fetch(@service_name) : ActiveStorage::Blob.service
        end
      end
    end
  end
end
