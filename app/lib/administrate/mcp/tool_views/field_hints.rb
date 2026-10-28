# frozen_string_literal: true

module Administrate
  module MCP
    module ToolViews
      # What a view needs to render a serialized value and follow it: the field's kind and, for an
      # association to a registered resource, that resource's name and the foreign key a filtered
      # list of it takes. Ships in the tool result's `_meta`, which a host hands to the view and
      # keeps out of the model's context. A resource the caller cannot list is left unnamed, as in the
      # catalog.
      module FieldHints
        META_KEY = 'administrate-mcp/view'

        ASSOCIATION_KINDS = %i[belongs_to has_many polymorphic].freeze

        URL_FIELD_CLASSES = ['Administrate::Field::Url'].freeze

        class << self
          def meta(entry, dashboard, attributes, admin:)
            return nil unless Administrate::MCP.config.tool_views

            resource = entry.model_class.name.underscore
            { META_KEY => { resource:, fields: fields(entry, dashboard, attributes, admin:) } }
          end

          def fields(entry, dashboard, attributes, admin:)
            FieldSerializer.resolve_columns(dashboard, attributes).to_h do |attr_name|
              kind = kind_for(dashboard.attribute_types[attr_name])
              hint = { kind: }
              if ASSOCIATION_KINDS.include?(kind)
                hint.merge!(association_hint(entry.model_class, attr_name, kind, admin))
              end
              [attr_name, hint]
            end
          end

          def kind_for(field_spec)
            field_class = FieldSerializer.resolve_field_class(field_spec)
            return :has_many if FieldSerializer.expandable_field?(field_class)
            return :url if url_field?(field_class)

            serializer = FieldSerializer.serializer_for(field_spec)
            serializer.is_a?(Symbol) ? serializer : :value
          end

          private

          def url_field?(field_class)
            return false unless field_class.is_a?(Class)

            field_class.ancestors.any? { |ancestor| URL_FIELD_CLASSES.include?(ancestor.name) }
          end

          def association_hint(model_class, attr_name, kind, admin)
            reflection = model_class.reflect_on_association(attr_name)
            return {} if reflection.nil? || reflection.polymorphic? || kind == :polymorphic

            resource = registered_resource(reflection.klass)
            return {} unless resource && AdminDashboardTool.readable?(admin, resource)

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
