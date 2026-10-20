# frozen_string_literal: true

module Administrate
  module MCP
    module Tools
      # Hands out presigned upload URLs, so a client can upload a file and then pass its upload_id
      # to an action that accepts uploads. Published only when `config.uploads.enabled` is set.
      class UploadsPrepare < BaseTool
        tool_name 'uploads_prepare'
        requires_scope :write
        description 'Prepare file uploads. Pass `files` as an object of filename to size in bytes. Each file gets ' \
                    'an `upload_id`, a presigned `url` and `headers`. Upload the file with an HTTP PUT to `url`, ' \
                    'sending every header in `headers`, for example ' \
                    '`curl -X PUT -H "Content-Type: image/png" --upload-file a.png "<url>"`. ' \
                    'Then pass the `upload_id` as `<attribute>_upload_id` to an action that accepts uploads. ' \
                    'URLs expire after 15 minutes by default and upload ids after an hour.'
        annotations(read_only_hint: false, destructive_hint: false, open_world_hint: true)

        input_schema(
          properties: {
            files: {
              type: 'object',
              description: 'Filename to size in bytes, for example {"logo.png": 48213}.',
              additionalProperties: { type: 'integer' }
            }
          },
          required: %w[files]
        )

        def self.execute(admin:, files:)
          json_response(Administrate::MCP::Uploads.prepare(admin:, files:))
        end
      end
    end
  end
end
