# frozen_string_literal: true

module Administrate
  module MCP
    # Presigned uploads. `prepare` checks that the caller may use the target action, records a
    # batch, and hands out one presigned upload per file. `resolve` turns an upload_id back into an
    # attachment value for that same action and attribute: it copies the uploaded object to a key
    # the client cannot write to, checks the copy's real size and content type, and remembers the
    # copy so a retried action gets the same file.
    module Uploads
      class << self
        def prepare(admin:, scopes:, tool:, attribute:, files:)
          definition = upload_action!(admin, scopes, tool.to_s, attribute.to_sym)
          rules = rules_for(definition, attribute.to_sym)
          storage = presignable_storage!
          entries = Entries.build(files, rules, storage, tool: tool.to_s, attribute: attribute.to_s)
          UploadBatch.create!(admin:, expires_at: config.batch_ttl.seconds.from_now, files: entries)

          entries.to_h do |entry|
            [entry[:filename], { upload_id: entry[:upload_id], **presign(storage, entry, rules) }]
          end
        end

        def resolve(admin:, upload_id:, tool:, attribute:, rules:)
          batch, entry = find_entry!(admin, upload_id.to_s, tool, attribute)
          return entry['value'] if entry['value']

          record_value(batch, upload_id.to_s, fetch!(upload_id, entry, rules).value)
        end

        def rules_for(definition, attribute)
          config.rules(**definition.uploads.fetch(attribute))
        end

        private

        def config
          Administrate::MCP.config.uploads
        end

        def upload_action!(admin, scopes, tool, attribute)
          definition = Actions.definitions.find { |candidate| Actions.tool_name(candidate) == tool }
          return definition if definition&.uploads&.key?(attribute) && Actions.available_to?(admin, definition, scopes:)

          raise InvalidArgumentError, "No action #{tool} that accepts an upload for #{attribute} is available to you"
        end

        def presignable_storage!
          storage = config.storage
          raise ConfigurationError, 'No upload storage is configured; set config.uploads.storage' unless storage
          return storage if storage.presignable?

          raise ConfigurationError, "#{storage.description} cannot presign uploads. Configure a storage that " \
                                    'can, such as Shrine::Storage::S3, or set config.uploads.storage'
        end

        def presign(storage, entry, rules)
          storage.presign(entry[:key], content_type: entry[:content_type], max_size: rules.max_size,
                                       expires_in: config.url_ttl.to_i, filename: entry[:filename],
                                       size: entry[:size], checksum: entry[:checksum])
        end

        def find_entry!(admin, upload_id, tool, attribute)
          batch = UploadBatch.with_upload(upload_id).find_by(admin:)
          raise InvalidArgumentError, "Upload #{upload_id} not found" unless batch
          raise InvalidArgumentError, "Upload #{upload_id} expired at #{batch.expires_at.iso8601}" if batch.expired?

          entry = batch.file(upload_id)
          unless entry['tool'] == tool && entry['attribute'] == attribute
            raise InvalidArgumentError, "Upload #{upload_id} was prepared for #{entry['tool']} #{entry['attribute']}"
          end

          [batch, entry]
        end

        def fetch!(upload_id, entry, rules)
          upload = config.storage.fetch(entry['key'], filename: entry['filename'], max_size: rules.max_size)
          raise InvalidArgumentError, "Upload #{upload_id} has not been uploaded yet" unless upload

          error = content_error(upload_id, upload, rules)
          return upload unless error

          config.storage.delete(upload.value)
          raise InvalidArgumentError, error
        end

        def record_value(batch, upload_id, value)
          UploadBatch.transaction do
            locked = UploadBatch.lock.find(batch.id)
            recorded = locked.file(upload_id)['value']
            next locked.record_value!(upload_id, value) && value unless recorded

            config.storage.delete(value)
            recorded
          end
        end

        def content_error(upload_id, upload, rules)
          if upload.size.to_i > rules.max_size
            "Upload #{upload_id} is #{upload.size} bytes, the maximum is #{rules.max_size}"
          elsif !rules.allowed_content_type?(upload.mime_type)
            "Upload #{upload_id} is #{upload.mime_type || 'of an unknown type'}, " \
              "expected one of #{rules.content_types.values.uniq.join(', ')}"
          end
        end
      end
    end
  end
end
