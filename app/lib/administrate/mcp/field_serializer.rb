# frozen_string_literal: true

module Administrate
  module MCP
    # Converts a record + dashboard definition into a plain Hash suitable for JSON.
    #
    # Field classes are matched by name against the configured registry, walking the field's
    # ancestors, so a host can register its own field classes without the engine ever referencing
    # a constant it does not own.
    class FieldSerializer
      MAX_EXPAND_ITEMS = 25

      # Where one attribute's value comes from. Administrate resolves a `getter:` option through the
      # field instance, never off the record, so an attribute declared only as a lambda has no
      # matching model method and `public_send` raises. Building the field is the only way to read
      # those.
      #
      # A getter is arbitrary code — several run their own queries — so `resolve_getters` is opt-in
      # and only single-record callers set it. Resolving them per row would turn one list call into
      # a query per row.
      AttributeSource =
        Struct.new(:record, :attr_name, :field_spec, :resolve_getters) do
          def value
            return field_spec.new(attr_name, nil, :show, resource: record).data if getter?

            record.public_send(attr_name)
          end

          def getter?
            resolve_getters && field_spec.is_a?(Administrate::Field::Deferred) && field_spec.getter.present?
          end
        end

      class << self
        def serialize(record, dashboard, attributes: nil, expand: nil, resolve_getters: false)
          attrs = attributes || dashboard.show_page_attributes
          attrs.each_with_object({ url: admin_url_for(record) }) do |attr_name, hash|
            field_spec = dashboard.attribute_types[attr_name]
            next unless field_spec

            next if skip_field?(resolve_field_class(field_spec))

            hash[attr_name] = serialize_single(
              AttributeSource.new(record, attr_name, field_spec, resolve_getters),
              expand
            )
          end
        end

        def admin_url_for(record)
          return nil unless record.is_a?(ActiveRecord::Base)

          klass = record.class
          while klass < ActiveRecord::Base && !klass.abstract_class?
            begin
              return polymorphic_admin_url(record.becomes(klass))
            rescue ActionController::UrlGenerationError, NoMethodError
              klass = klass.superclass
            end
          end
          nil
        end

        def polymorphic_admin_url(record)
          config = Administrate::MCP.config
          Rails.application.routes.url_helpers.polymorphic_url(
            [config.admin_route_namespace, record],
            **config.admin_url_options
          )
        end

        def resolve_columns(dashboard, attributes)
          (attributes || dashboard.show_page_attributes).select do |attr_name|
            field_spec = dashboard.attribute_types[attr_name]
            next false unless field_spec

            !skip_field?(resolve_field_class(field_spec))
          end
        end

        def serialize_row(record, dashboard, columns:, expand: nil, resolve_getters: false)
          columns.map do |attr_name|
            source = AttributeSource.new(record, attr_name, dashboard.attribute_types[attr_name], resolve_getters)
            serialize_single(source, expand)
          end
        end

        def serialize_single(source, expand)
          field_class = resolve_field_class(source.field_spec)
          if expand&.include?(source.attr_name) && expandable_field?(field_class)
            serialize_has_many_expanded(source)
          else
            serialize_field(source, field_class)
          end
        end

        def expandable_field?(field_class)
          return false unless field_class.is_a?(Class)

          matches?(field_class, Administrate::MCP.config.has_many_field_classes)
        end

        def resolve_field_class(field_spec)
          case field_spec
          when Administrate::Field::Deferred
            field_spec.deferred_class
          when Class
            field_spec
          end
        end

        def skip_field?(field_class)
          return true unless field_class

          matches?(field_class, Administrate::MCP.config.skipped_field_classes)
        end

        def serialize_field(source, field_class)
          serializer = lookup_serializer(field_class)
          return serializer.call(source) if serializer.respond_to?(:call)
          return send(:"serialize_#{serializer}", source) if serializer
          return field_class.mcp_value(source.record, source.attr_name) if field_class.respond_to?(:mcp_value)

          serialize_unknown(source)
        rescue StandardError
          "[error: could not serialize #{source.attr_name}]"
        end

        def serialize_has_many(source)
          relation = has_many_relation(source)
          return nil unless relation

          { count: relation_count(relation) }
        rescue StandardError
          nil
        end

        def serialize_has_many_expanded(source)
          relation = has_many_relation(source)
          return nil unless relation

          { count: relation_count(relation), items: expanded_items(relation) }
        rescue StandardError
          nil
        end

        def has_many_relation(source) # rubocop:disable Naming/PredicatePrefix
          value = source.value
          value.is_a?(ActiveRecord::Relation) ? value : nil
        end

        def expanded_items(relation)
          related_records = relation.limit(MAX_EXPAND_ITEMS)
          dashboard_class = "#{relation.klass.name}Dashboard".safe_constantize
          return related_records.map(&:to_s) unless dashboard_class

          dash = dashboard_class.new
          related_records.map { |r| serialize(r, dash, attributes: dash.collection_attributes) }
        end

        def relation_count(relation)
          return relation.count if relation.select_values.blank?

          relation.klass.from(relation.unscope(:order).arel.as('mcp_count_sub')).count
        end

        def serialize_belongs_to(source)
          related = source.value
          related ? build_related_hash(related) : nil
        rescue StandardError
          nil
        end

        # A polymorphic association is useless to a caller without its type: the id alone names no
        # table. Both halves ship in the hash.
        def serialize_polymorphic(source)
          related = source.value
          return nil unless related

          build_related_hash(related).merge(type: related.class.name)
        rescue StandardError
          nil
        end

        def serialize_datetime(source)
          source.value&.iso8601
        end

        def serialize_enum(source)
          source.value.to_s
        end

        def serialize_attachment(source)
          value = source.value
          return nil unless value

          value.try(:url) || value.to_s
        rescue StandardError
          nil
        end

        def serialize_scalar(source)
          source.value
        end

        def serialize_unknown(source)
          value = source.value
          return value if value.nil? || value.is_a?(Numeric) || [true, false].include?(value)
          return value if value.is_a?(String) || value.is_a?(Hash) || value.is_a?(Array)

          value.to_s
        end

        def build_related_hash(related)
          display = display_resource_for(related)
          result = { id: related.id }
          result[:display] = display if display != "#{related.class.name.demodulize} ##{related.id}"
          result[:slug] = related.slug if related.respond_to?(:slug)
          result
        end

        def display_resource_for(related)
          dashboard_class = "#{related.class.name}Dashboard".safe_constantize
          return related.to_s unless dashboard_class

          dashboard_class.new.display_resource(related)
        rescue StandardError
          related.to_s
        end

        private

        def lookup_serializer(field_class)
          return nil unless field_class.is_a?(Class)

          registry = Administrate::MCP.config.field_serializers
          field_class.ancestors.each do |ancestor|
            name = ancestor.name
            next unless name

            entry = registry[name]
            return entry if entry
          end
          nil
        end

        def matches?(field_class, class_names)
          names = field_class.ancestors.filter_map(&:name)
          class_names.any? { |candidate| names.include?(candidate.to_s) }
        end
      end
    end
  end
end
