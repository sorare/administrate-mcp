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
        def prepare(admin:, tool:, attribute:, files:)
          definition = upload_action!(admin, tool.to_s, attribute.to_sym)
          rules = rules_for(definition, attribute.to_sym)
          storage = presignable_storage!
          entries = build_entries(files, rules, tool: tool.to_s, attribute: attribute.to_s)
          UploadBatch.create!(admin:, expires_at: config.batch_ttl.seconds.from_now, files: entries)

          entries.to_h do |entry|
            presigned = storage.presign(entry[:key], content_type: entry[:content_type], max_size: rules.max_size,
                                                     expires_in: config.url_ttl.to_i)
            [entry[:filename], { upload_id: entry[:upload_id], **presigned }]
          end
        end

        def resolve(admin:, upload_id:, tool:, attribute:, rules:)
          UploadBatch.transaction do
            batch, entry = find_entry!(admin, upload_id.to_s, tool, attribute)
            next entry['value'] if entry['value']

            value = fetch!(upload_id, entry, rules).value
            batch.record_value!(upload_id.to_s, value)
            value
          end
        end

        def available?(server_context)
          config.enabled && Actions.tools_for(server_context).any? { |tool| tool.definition.uploads.any? }
        end

        def rules_for(definition, attribute)
          config.rules(**definition.uploads.fetch(attribute))
        end

        private

        def config
          Administrate::MCP.config.uploads
        end

        def upload_action!(admin, tool, attribute)
          definition = Actions.definitions.find { |candidate| Actions.tool_name(candidate) == tool }
          return definition if definition&.uploads&.key?(attribute) && Actions.available_to?(admin, definition)

          raise InvalidArgumentError, "No action #{tool} that accepts an upload for #{attribute} is available to you"
        end

        def presignable_storage!
          storage = config.storage
          raise ConfigurationError, 'No upload storage is configured; set config.uploads.storage' unless storage
          return storage if storage.presignable?

          raise ConfigurationError, "#{storage.description} cannot presign uploads. Configure a storage that " \
                                    'can, such as Shrine::Storage::S3, or set config.uploads.storage'
        end

        def build_entries(files, rules, **target)
          raise InvalidArgumentError, 'files must name at least one file' if files.blank?
          if files.size > config.max_files
            raise InvalidArgumentError, "files can name at most #{config.max_files} files"
          end

          errors = files.flat_map { |filename, size| entry_errors(filename.to_s, size, rules) }
          raise InvalidArgumentError, errors.join('; ') if errors.any?

          files.map { |filename, size| build_entry(filename.to_s, Integer(size), rules, **target) }
        end

        def entry_errors(filename, size, rules)
          errors = []
          unless rules.content_type_for(filename)
            errors << "#{filename} is not an allowed file type (#{rules.content_types.keys.join(', ')})"
          end
          unless Integer(size, exception: false)&.between?(1, rules.max_size)
            errors << "#{filename} size must be between 1 and #{rules.max_size} bytes"
          end
          errors
        end

        def build_entry(filename, size, rules, tool:, attribute:)
          upload_id = SecureRandom.uuid
          extension = File.extname(filename).downcase
          { upload_id:, key: "#{upload_id}#{extension}", filename:, content_type: rules.content_type_for(filename),
            size:, tool:, attribute: }
        end

        def find_entry!(admin, upload_id, tool, attribute)
          batch = UploadBatch.with_upload(upload_id).lock.find_by(admin:)
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

          check_content!(upload_id, upload, rules)
          upload
        end

        def check_content!(upload_id, upload, rules)
          if upload.size.to_i > rules.max_size
            raise InvalidArgumentError, "Upload #{upload_id} is #{upload.size} bytes, the maximum is #{rules.max_size}"
          end
          return if rules.allowed_content_type?(upload.mime_type)

          raise InvalidArgumentError, "Upload #{upload_id} is #{upload.mime_type || 'of an unknown type'}, " \
                                      "expected one of #{rules.content_types.values.uniq.join(', ')}"
        end
      end
    end
  end
end
