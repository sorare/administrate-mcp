# frozen_string_literal: true

module Administrate
  module MCP
    # Generates self-describing MCP tools from the custom write actions declared on dashboards.
    #
    # A dashboard declares an action with `mcp_action`, alongside its MCP_DESCRIPTION — so one file
    # defines a resource's full MCP contract (readable fields + writable actions). From each
    # declaration we build a tool whose name, input schema and description let non-developer users
    # discover and call it through the protocol.
    #
    # Enforcement is layered: the generated tool requires an OAuth `write` scope (the rollout gate)
    # AND runs the resource's authorization predicate against the loaded record (the per-admin
    # truth, identical to the admin UI). Auditing is inherited from BaseTool.
    module Actions
      Definition =
        Struct.new(
          :model_class,
          :name,
          :predicate,
          :scope,
          :destructive,
          :description,
          :params,
          :required,
          :invoke,
          keyword_init: true
        )

      class << self
        # Normalizes the arguments of a `mcp_action` declaration into a spec (everything but the
        # model, which is inferred from the owning dashboard when definitions are built).
        def build_spec(name, description:, params: {}, predicate: nil, pundit: nil, scope: :write,
                       destructive: true, &invoke)
          raise ArgumentError, "#{name}: a block is required to invoke the action" unless invoke

          normalized =
            params.transform_values { |spec| spec.is_a?(String) ? { type: 'string', description: spec } : spec }

          {
            name: name.to_sym,
            predicate: (predicate || pundit || :"#{name}?").to_sym,
            scope: scope.to_sym,
            destructive:,
            description:,
            params: normalized.transform_values { |spec| spec.except(:required) },
            required: normalized.reject { |_, spec| spec[:required] == false }.keys,
            invoke:
          }
        end

        def definitions
          @definitions ||=
            DashboardRegistry.registry.values.flat_map do |entry|
              next [] unless entry.dashboard_class.respond_to?(:mcp_action_specs)

              entry.dashboard_class.mcp_action_specs.map do |spec|
                Definition.new(model_class: entry.model_class, **spec)
              end
            end
        end

        def all_tools
          @all_tools ||= definitions.map { |defn| ToolFactory.build(defn) }
        end

        # Tool classes the caller may both see and run: write scope granted AND the authorization
        # predicate satisfied at the role level. The actual call re-checks it against the record.
        def tools_for(server_context)
          granted = (server_context[:scopes] || []).map(&:to_sym)
          admin = server_context[:admin]

          all_tools.select do |tool|
            defn = tool.definition
            granted.include?(defn.scope) && authorized_for_discovery?(admin, defn)
          end
        end

        def reset!
          @definitions = nil
          @all_tools = nil
        end

        def find_record!(model_class, id)
          record = model_class.find_by(id:) || friendly_find(model_class, id)
          raise UnauthorizedError, "#{model_class.name} not found: #{id}" unless record

          record
        end

        def authorize!(admin, record, predicate)
          Administrate::MCP.config.authorization.authorize!(admin, record, predicate)
        end

        private

        def authorized_for_discovery?(admin, definition)
          Administrate::MCP.config.authorization.authorized?(admin, definition.model_class, definition.predicate)
        rescue StandardError
          false
        end

        def friendly_find(model_class, id)
          return nil unless model_class.respond_to?(:friendly)

          model_class.friendly.find(id)
        rescue ActiveRecord::RecordNotFound
          nil
        end
      end

      # Turns one Definition into an anonymous BaseTool subclass.
      module ToolFactory
        class << self
          def build(defn)
            resource = defn.model_class.name.underscore
            klass = Class.new(BaseTool)
            klass.tool_name "#{resource.tr('/', '_')}_#{defn.name}"
            klass.description defn.description
            klass.annotations(read_only_hint: false, destructive_hint: defn.destructive, open_world_hint: true)
            klass.requires_scope defn.scope
            klass.input_schema(**schema_for(defn, resource))
            define_behaviors(klass, defn)
            klass
          end

          def schema_for(defn, resource)
            properties = { id: { type: 'string', description: "ID or slug of the #{resource}" } }
            defn.params.each { |name, spec| properties[name] = spec }
            { properties:, required: %w[id] + defn.required.map(&:to_s) }
          end

          # Replaces the role-based default with instance-level authorization on the loaded record.
          def authorize!(defn, admin, id)
            record = Actions.find_record!(defn.model_class, id)
            Actions.authorize!(admin, record, defn.predicate)
          end

          def invoke(defn, admin, id, params)
            record = Actions.find_record!(defn.model_class, id)
            result = defn.invoke.call(record:, admin:, params:)
            return { error: result.try(:error) || "#{defn.name} failed" } if failed?(result)

            { data: { status: 'ok', model: defn.model_class.name.underscore, id:, action: defn.name.to_s } }
          end

          private

          def define_behaviors(klass, defn)
            klass.define_singleton_method(:definition) { defn }
            klass.define_singleton_method(:check_roles!) do |admin, id: nil, **|
              ToolFactory.authorize!(defn, admin, id)
            end
            klass.define_singleton_method(:execute) do |admin:, id:, **params|
              outcome = ToolFactory.invoke(defn, admin, id, params)
              outcome.key?(:error) ? error_response(outcome[:error]) : json_response(outcome[:data])
            end
          end

          def failed?(result)
            result.respond_to?(:success?) && !result.success?
          end
        end
      end
    end
  end
end
