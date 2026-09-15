# frozen_string_literal: true

module Administrate
  module MCP
    # Base class for MCP tools that operate on Administrate dashboard resources.
    class AdminDashboardTool < BaseTool
      LISTED_VALID_VALUES = 40

      class << self
        def policy_action
          nil
        end

        def check_roles!(admin, resource: nil, **)
          return unless resource && policy_action

          entry = find_dashboard_entry!(resource)
          authorize_resource!(admin, entry.model_class, policy_action)
        end

        def authorized?(admin, model_class, action)
          Administrate::MCP.config.authorization.authorized?(admin, model_class, action)
        end

        def authorize_resource!(admin, model_class, action)
          Administrate::MCP.config.authorization.authorize!(admin, model_class, action)
        end

        def find_dashboard_entry!(resource_name)
          entry = DashboardRegistry.find(resource_name)
          return entry if entry

          raise UnauthorizedError, "Unknown resource: #{resource_name}"
        end

        def reject_unknown!(kind, given, allowed)
          allowed = allowed.to_a.map(&:to_s).sort
          unknown = Array.wrap(given).map(&:to_s) - allowed
          return if unknown.empty?

          raise InvalidArgumentError,
                "Unknown #{kind}: #{unknown.sort.join(', ')}. " \
                "Valid #{kind} for this resource: #{listed(allowed)}"
        end

        def reject_over_limit!(kind, size, max)
          return if size <= max

          raise InvalidArgumentError, "Too many #{kind}: #{size} requested, at most #{max} are allowed per call."
        end

        def listed(allowed)
          return 'none' if allowed.empty?
          return allowed.join(', ') if allowed.size <= LISTED_VALID_VALUES

          "#{allowed.first(LISTED_VALID_VALUES).join(', ')} " \
            "(+#{allowed.size - LISTED_VALID_VALUES} more, see admin_resource_list_resources)"
        end

        def resolve_attributes(dashboard, fields, default_method)
          return dashboard.public_send(default_method) if fields.blank?

          reject_unknown!('fields', fields, dashboard.show_page_attributes)

          fields.map(&:to_sym)
        end

        # An expansion only applies to an attribute the response carries, so an expanded association
        # is added to the returned attributes rather than quietly doing nothing.
        def resolve_attributes_and_expansions(dashboard, fields, expand, default_method, max_expand)
          attrs = resolve_attributes(dashboard, fields, default_method)
          expand_set = validated_expand_set(dashboard, expand, attrs, max_expand)
          return attrs, nil unless expand_set

          [attrs | expand_set.to_a, expand_set]
        end

        # Expandable names stay bounded by show_page_attributes so an expansion cannot surface an
        # attribute the dashboard withholds from its show page.
        def validated_expand_set(dashboard, expand, attributes, max_expand)
          return nil if expand.blank?

          expandable = expandable_attributes(dashboard) & (dashboard.show_page_attributes.to_a | attributes.to_a)
          reject_unknown!('expandable associations', expand, expandable)
          reject_over_limit!('expansions', expand.size, max_expand)

          expand.to_set(&:to_sym)
        end

        def expandable_attributes(dashboard)
          dashboard
            .attribute_types
            .select { |_, spec| FieldSerializer.expandable_field?(FieldSerializer.resolve_field_class(spec)) }
            .keys
        end

        def association_columns(model_class)
          column_names = model_class.column_names.to_set
          model_class
            .reflect_on_all_associations(:belongs_to)
            .each_with_object(Set.new) do |reflection, columns|
              fk = reflection.foreign_key.to_s
              columns << fk if column_names.include?(fk)
              next unless reflection.options[:polymorphic]

              ft = reflection.foreign_type.to_s
              columns << ft if column_names.include?(ft)
            end
        end
      end
    end
  end
end
