# frozen_string_literal: true

require 'did_you_mean'

module Administrate
  module MCP
    # Base class for MCP tools that operate on Administrate dashboard resources.
    class AdminDashboardTool < BaseTool
      LISTED_VALID_VALUES = 40
      MAX_SUGGESTIONS = 5
      ACTION_VERBS = { index?: 'list', show?: 'show' }.freeze

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

        # The adapter is the host's and raises a plain UnauthorizedError. Re-raised here so a denial on
        # one resource reaches the caller as a tool error instead of a 403 on the whole response.
        def authorize_resource!(admin, model_class, action)
          Administrate::MCP.config.authorization.authorize!(admin, model_class, action)
        rescue UnauthorizedError
          verb = ACTION_VERBS.fetch(action.to_sym) { action.to_s.delete_suffix('?') }
          raise ResourceForbiddenError,
                "Resource `#{model_class.name.underscore}` exists but your role is not authorized to #{verb} it."
        end

        def find_dashboard_entry!(resource_name)
          entry = DashboardRegistry.find(resource_name)
          return entry if entry

          raise InvalidArgumentError, unknown_resource_message(resource_name)
        end

        def unknown_resource_message(resource_name)
          message = "Unknown resource: #{resource_name}. This name is not registered."
          suggestions = resource_suggestions(resource_name)
          return "#{message} Call admin_resource_list_resources for the catalog." if suggestions.empty?

          "#{message} Closest registered names: #{suggestions.join(', ')}"
        end

        # Matches on the last path segment too, so a bare "order" finds "shop/order".
        def resource_suggestions(resource_name)
          key = resource_name.to_s.underscore.singularize
          names = DashboardRegistry.resource_names
          by_segment = names.group_by { |name| name.split('/').last }
          segment = key.split('/').last.to_s
          close_segments = DidYouMean::SpellChecker.new(dictionary: by_segment.keys).correct(segment)

          (
            by_segment.fetch(segment, []) +
              DidYouMean::SpellChecker.new(dictionary: names).correct(key) +
              close_segments.flat_map { |name| by_segment[name] }
          ).uniq.first(MAX_SUGGESTIONS)
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

          reject_unknown!('fields', fields, FieldSerializer.exposed_attributes(dashboard))

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

          exposed = FieldSerializer.exposed_attributes(dashboard) | attributes.to_a
          expandable = expandable_attributes(dashboard) & exposed
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
