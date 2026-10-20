# frozen_string_literal: true

module Administrate
  module MCP
    # Presigned uploads. `prepare` records a batch and hands out one presigned PUT per file;
    # `resolve` turns an upload_id back into an attachment value once its admin has uploaded the
    # file. The declared size is checked up front and the real size again on resolve, because a
    # presigned PUT does not sign Content-Length, so the storage accepts any size.
    module Uploads
      class << self
        def prepare(admin:, files:)
          storage = presignable_storage!
          entries = build_entries(files)
          UploadBatch.create!(admin:, expires_at: config.batch_ttl.seconds.from_now, files: entries)

          entries.to_h do |entry|
            presigned = storage.presign(entry[:key], content_type: entry[:content_type],
                                                     expires_in: config.url_ttl.to_i)
            [entry[:filename], { upload_id: entry[:upload_id], **presigned }]
          end
        end

        def resolve(admin:, upload_id:)
          entry = find_entry!(admin, upload_id.to_s)
          upload = config.storage.fetch(entry['key'], filename: entry['filename'])
          raise InvalidArgumentError, "Upload #{upload_id} has not been uploaded yet" unless upload

          check_content!(upload_id, upload)
          upload.value
        end

        def action_attributes(dashboard_class, action_name, declared)
          return [] if declared.blank? || !config.enabled

          attachments = attachment_attributes(dashboard_class)
          return attachments if declared == true

          unknown = declared - attachments
          return declared if unknown.empty?

          raise ArgumentError, "#{dashboard_class.name} #{action_name}: uploads: names #{unknown.join(', ')}, " \
                               'which are not attachment attributes'
        end

        def param_schemas(attributes)
          attributes.to_h do |attribute|
            [param_name(attribute),
             { type: 'string', description: "An upload_id from uploads_prepare, to set #{attribute} to that file." }]
          end
        end

        def resolve_params(attributes, admin, params)
          attributes.each_with_object(params.dup) do |attribute, resolved|
            upload_id = resolved.delete(param_name(attribute))
            resolved[attribute] = resolve(admin:, upload_id:) if upload_id.present?
          end
        end

        private

        def param_name(attribute)
          :"#{attribute}_upload_id"
        end

        def attachment_attributes(dashboard_class)
          dashboard_class.new.attribute_types.filter_map do |attribute, field_spec|
            attribute if FieldSerializer.serializer_for(field_spec) == :attachment
          end
        end

        def config
          Administrate::MCP.config.uploads
        end

        def presignable_storage!
          storage = config.storage
          raise ConfigurationError, 'No upload storage is configured; set config.uploads.storage' unless storage
          return storage if storage.presignable?

          raise ConfigurationError, "#{storage.description} cannot presign uploads. Configure a storage that " \
                                    'can, such as Shrine::Storage::S3, or set config.uploads.storage'
        end

        def build_entries(files)
          raise InvalidArgumentError, 'files must name at least one file' if files.blank?

          errors = files.flat_map { |filename, size| entry_errors(filename.to_s, size) }
          raise InvalidArgumentError, errors.join('; ') if errors.any?

          files.map { |filename, size| build_entry(filename.to_s, Integer(size)) }
        end

        def entry_errors(filename, size)
          errors = []
          unless config.content_type_for(filename)
            errors << "#{filename} is not an allowed file type (#{config.allowed_content_types.keys.join(', ')})"
          end
          unless Integer(size, exception: false)&.between?(1, config.max_size)
            errors << "#{filename} size must be between 1 and #{config.max_size} bytes"
          end
          errors
        end

        def build_entry(filename, size)
          upload_id = SecureRandom.uuid
          extension = File.extname(filename).downcase
          { upload_id:, key: "#{upload_id}#{extension}", filename:, content_type: config.content_type_for(filename),
            size: }
        end

        def find_entry!(admin, upload_id)
          batch = UploadBatch.with_upload(upload_id).find_by(admin:)
          raise InvalidArgumentError, "Upload #{upload_id} not found" unless batch
          raise InvalidArgumentError, "Upload #{upload_id} expired at #{batch.expires_at.iso8601}" if batch.expired?

          batch.file(upload_id)
        end

        def check_content!(upload_id, upload)
          unless config.allowed_content_type?(upload.mime_type)
            raise InvalidArgumentError, "Upload #{upload_id} is #{upload.mime_type || 'of an unknown type'}, " \
                                        "expected one of #{config.allowed_content_types.values.uniq.join(', ')}"
          end
          return if upload.size.to_i <= config.max_size

          raise InvalidArgumentError, "Upload #{upload_id} is #{upload.size} bytes, the maximum is #{config.max_size}"
        end
      end
    end
  end
end
