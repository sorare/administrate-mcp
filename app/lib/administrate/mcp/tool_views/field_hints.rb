# frozen_string_literal: true

module Administrate
  module MCP
    module ToolViews
      # What a view needs to render a serialized value and follow it: the field's kind and, for an
      # association to a registered resource, that resource's name and the foreign key a filtered
      # list of it takes. Ships in the tool result's `_meta`, which a host hands to the view and
      # keeps out of the model's context.
      module FieldHints
        META_KEY = 'administrate-mcp/view'

        ASSOCIATION_KINDS = %i[belongs_to has_many polymorphic].freeze

        class << self
          def meta(entry, dashboard, attributes)
            return nil unless Administrate::MCP.config.tool_views

            resource = entry.model_class.name.underscore
            { META_KEY => { resource:, fields: fields(entry, dashboard, attributes) } }
          end

          def fields(entry, dashboard, attributes)
            FieldSerializer.resolve_columns(dashboard, attributes).to_h do |attr_name|
              field_spec = dashboard.attribute_types[attr_name]
              kind = kind_for(field_spec)
              hint = { kind: }
              hint.merge!(association_hint(entry.model_class, attr_name, kind)) if ASSOCIATION_KINDS.include?(kind)
              [attr_name, hint]
            end
          end

          def kind_for(field_spec)
            field_class = FieldSerializer.resolve_field_class(field_spec)
            return :has_many if FieldSerializer.expandable_field?(field_class)

            serializer = FieldSerializer.serializer_for(field_spec)
            serializer.is_a?(Symbol) ? serializer : :value
          end

          private

          def association_hint(model_class, attr_name, kind)
            reflection = model_class.reflect_on_association(attr_name)
            return {} if reflection.nil? || reflection.polymorphic? || kind == :polymorphic

            resource = registered_resource(reflection.klass)
            return {} unless resource

            { resource:, foreign_key: filter_key(reflection, kind) }.compact
          rescue NameError
            {}
          end

          def filter_key(reflection, kind)
            reflection.foreign_key.to_s if kind == :has_many && !reflection.through_reflection?
          end

          def registered_resource(model_class)
            name = model_class.name.underscore
            DashboardRegistry.registry.key?(name) ? name : nil
          end
        end
      end
    end
  end
end
