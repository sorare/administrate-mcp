# frozen_string_literal: true

module Administrate
  module MCP
    module Uploads
      # How an `mcp_action` declares uploads: which attachment attributes take an
      # `<attribute>_upload_id`, the schema of those params, and turning them into attachment
      # values before the action's block runs.
      module Declarations
        RULE_KEYS = %i[content_types max_size].freeze

        class << self
          def normalize(uploads, action_name:)
            return true if uploads == true
            return {} unless uploads
            return Array(uploads).to_h { |attribute| [attribute.to_sym, {}] } unless uploads.is_a?(Hash)

            uploads.to_h do |attribute, rules|
              [attribute.to_sym, validate_rules!("#{action_name}: uploads: #{attribute}", rules)]
            end
          end

          def any?(action_tools)
            config.enabled && action_tools.any? { |tool| tool.definition.uploads.any? }
          end

          def action_attributes(dashboard_class, action_name, declared)
            return {} if declared.blank? || !config.enabled

            attachments = attachment_attributes(dashboard_class)
            if declared == true
              return attachments.index_with({}) if attachments.any?

              raise ArgumentError, "#{dashboard_class.name} #{action_name}: uploads: true, but the dashboard has " \
                                   'no attachment attribute'
            end

            unknown = declared.keys - attachments
            return declared if unknown.empty?

            raise ArgumentError, "#{dashboard_class.name} #{action_name}: uploads: names #{unknown.join(', ')}, " \
                                 'which are not attachment attributes'
          end

          def param_schemas(definition)
            definition.uploads.keys.to_h do |attribute|
              [param_name(attribute),
               { type: 'string', description: "An upload_id from uploads_prepare, to set #{attribute} to that file." }]
            end
          end

          def resolve_params(definition, admin, params)
            tool = Actions.tool_name(definition)
            definition.uploads.each_key.with_object(params.dup) do |attribute, resolved|
              upload_id = resolved.delete(param_name(attribute))
              next if upload_id.blank?

              resolved[attribute] = Uploads.resolve(admin:, upload_id:, tool:, attribute: attribute.to_s,
                                                    rules: Uploads.rules_for(definition, attribute))
            end
          end

          private

          def validate_rules!(context, rules)
            raise ArgumentError, "#{context} must be a hash of rules" unless rules.is_a?(Hash)

            rules = rules.symbolize_keys
            unknown = rules.keys - RULE_KEYS
            raise ArgumentError, "#{context}: unknown rule(s) #{unknown.join(', ')}" if unknown.any?
            unless rules[:content_types].nil? || content_types?(rules[:content_types])
              raise ArgumentError, "#{context}: content_types: must be a hash of extension to content type, " \
                                   "such as { '.png' => 'image/png' }"
            end
            return rules if rules[:max_size].nil? || positive_integer?(rules[:max_size])

            raise ArgumentError, "#{context}: max_size: must be a positive number of bytes"
          end

          def positive_integer?(value)
            value.is_a?(Integer) && value.positive?
          end

          def content_types?(content_types)
            content_types.is_a?(Hash) && content_types.any? &&
              content_types.all? { |extension, type| extension.to_s.match?(/\A\.\w+\z/) && type.is_a?(String) }
          end

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
        end
      end
    end
  end
end
