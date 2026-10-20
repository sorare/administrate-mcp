# frozen_string_literal: true

module Administrate
  module MCP
    module Uploads
      # Turns the `files` of an `uploads_prepare` call into batch entries. Each file is a size in
      # bytes, or a size and the base64-encoded MD5 checksum, which a storage that signs it requires.
      # Every file is checked before any entry is built, so a refused call records nothing.
      module Entries
        class << self
          def build(files, rules, storage, **target)
            raise InvalidArgumentError, 'files must name at least one file' if files.blank?

            max_files = Administrate::MCP.config.uploads.max_files
            raise InvalidArgumentError, "files can name at most #{max_files} files" if files.size > max_files

            files = files.to_h { |filename, file| [filename.to_s, file_spec(file)] }
            errors = files.flat_map { |filename, file| entry_errors(filename, file, rules, storage) }
            raise InvalidArgumentError, errors.join('; ') if errors.any?

            files.map { |filename, file| build_entry(filename, file, rules, **target) }
          end

          private

          def file_spec(file)
            file.is_a?(Hash) ? file.symbolize_keys.slice(:size, :checksum) : { size: file }
          end

          def entry_errors(filename, file, rules, storage)
            errors = []
            unless rules.content_type_for(filename)
              errors << "#{filename} is not an allowed file type (#{rules.content_types.keys.join(', ')})"
            end
            unless Integer(file[:size], exception: false)&.between?(1, rules.max_size)
              errors << "#{filename} size must be between 1 and #{rules.max_size} bytes"
            end
            errors + checksum_errors(filename, file[:checksum], storage)
          end

          def checksum_errors(filename, checksum, storage)
            if checksum.blank?
              return [] unless storage.respond_to?(:checksum_required?) && storage.checksum_required?

              return ["#{filename} needs a checksum, the base64-encoded MD5 digest of the file, because " \
                      "#{storage.description} signs it"]
            end
            return [] if md5_digest?(checksum)

            ["#{filename} checksum must be the base64-encoded MD5 digest of the file"]
          end

          def md5_digest?(checksum)
            checksum.is_a?(String) && Base64.strict_decode64(checksum).bytesize == 16
          rescue ArgumentError
            false
          end

          def build_entry(filename, file, rules, tool:, attribute:)
            upload_id = SecureRandom.uuid
            extension = File.extname(filename).downcase
            { upload_id:, key: "#{upload_id}#{extension}", filename:, content_type: rules.content_type_for(filename),
              size: Integer(file[:size]), checksum: file[:checksum].presence, tool:, attribute: }.compact
          end
        end
      end
    end
  end
end
