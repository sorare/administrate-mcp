# frozen_string_literal: true

module Administrate
  module MCP
    module Tools
      # Hands out presigned upload URLs for one attachment attribute of one action, so a client can
      # upload a file and then pass its upload_id to that action. Published only when uploads are
      # enabled and the caller has an action that accepts uploads.
      class UploadsPrepare < BaseTool
        tool_name 'uploads_prepare'
        requires_scope :write
        description 'Prepare file uploads for an action that accepts them. Pass the action\'s `tool` name, the ' \
                    '`attribute` the files are for (the action takes `<attribute>_upload_id`), and `files` as an ' \
                    'object of filename to size in bytes, or to `{"size": ..., "checksum": ...}` where checksum is ' \
                    'the base64-encoded MD5 digest of the file (`openssl md5 -binary logo.png | base64`); a ' \
                    'storage that signs the checksum requires it. Each file gets an `upload_id`, a `method`, a `url` ' \
                    'and either `fields` or `headers`. For `POST`, send a multipart form to `url` with every entry ' \
                    'of `fields` followed by the file as `file`, for example ' \
                    '`curl -F key=... -F policy=... (one -F per field) -F file=@logo.png "<url>"`. For `PUT`, ' \
                    'send the file as the body with every header in `headers`. Then pass the `upload_id` as ' \
                    '`<attribute>_upload_id` to that action. URLs expire after 15 minutes by default and upload ' \
                    'ids after an hour.'
        annotations(read_only_hint: false, destructive_hint: false, open_world_hint: true)

        input_schema(
          properties: {
            tool: { type: 'string', description: 'The action tool the files are for, for example widget_update.' },
            attribute: { type: 'string', description: 'The attachment attribute, for example picture.' },
            files: {
              type: 'object',
              description: 'Filename to size in bytes, for example {"logo.png": 48213}, or to size and checksum, ' \
                           'for example {"logo.png": {"size": 48213, "checksum": "CY9rzUYh03PK3k6DJie09g=="}}.',
              additionalProperties: {
                anyOf: [
                  { type: 'integer' },
                  {
                    type: 'object',
                    properties: {
                      size: { type: 'integer' },
                      checksum: { type: 'string', description: 'The base64-encoded MD5 digest of the file.' }
                    },
                    required: %w[size],
                    additionalProperties: false
                  }
                ]
              }
            }
          },
          required: %w[tool attribute files],
          additionalProperties: false
        )

        def self.execute(admin:, scopes:, tool:, attribute:, files:)
          json_response(Administrate::MCP::Uploads.prepare(admin:, scopes:, tool:, attribute:, files:))
        end

        def self.execute_context(server_context)
          { scopes: server_context[:scopes] || [] }
        end
        private_class_method :execute_context
      end
    end
  end
end
