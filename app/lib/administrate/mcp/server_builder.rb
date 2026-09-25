# frozen_string_literal: true

module Administrate
  module MCP
    # Builds a configured MCP::Server instance with auto-discovered tools.
    class ServerBuilder
      BUILT_IN_TOOLS = %w[
        Administrate::MCP::Tools::AdminResourceList
        Administrate::MCP::Tools::AdminResourceShow
        Administrate::MCP::Tools::AdminResourceListResources
      ].freeze

      REPORT_IMPROVEMENT_TOOL = 'Administrate::MCP::Tools::ReportImprovement'

      SIDEKIQ_RETRIES_TOOL = 'Administrate::MCP::Tools::SidekiqRetries'

      SIDEKIQ_STATS_TOOL = 'Administrate::MCP::Tools::SidekiqStats'

      class << self
        def build(server_context:)
          server_context[:authorization_errors] ||= []
          config = Administrate::MCP.config
          server =
            ::MCP::Server.new(
              name: config.server_name,
              version: config.server_version,
              tools: discover_tools(server_context),
              server_context:
            )
          server.transport =
            ::MCP::Server::Transports::StreamableHTTPTransport.new(
              server,
              stateless: true,
              # The gem's Host/Origin check guards against DNS rebinding on locally-bound servers.
              # The host's own route constraints already restrict which Host values reach the
              # controller, and this is not loopback-bound. Passing the incoming request's own host
              # back as `allowed_hosts:` would just validate the Host header against itself.
              dns_rebinding_protection: false,
              # `subscriptions/listen` answers with a streaming SSE body that is held open. The
              # controller buffers the response and builds a stateless transport per request, so it
              # cannot serve that stream; refusing answers the method as unimplemented (-32601).
              serve_subscriptions_listen: false
            )
          server
        end

        def discover_tools(server_context)
          load_host_tools
          (built_in_tools + host_tools).uniq + Actions.tools_for(server_context)
        end

        def built_in_tools
          names = BUILT_IN_TOOLS.dup
          names << REPORT_IMPROVEMENT_TOOL if Administrate::MCP.config.feedback_tool
          names << SIDEKIQ_RETRIES_TOOL if defined?(::Sidekiq)
          names << SIDEKIQ_STATS_TOOL if defined?(::Sidekiq) && Administrate::MCP.config.sidekiq_stats_provider
          names.filter_map(&:safe_constantize)
        end

        def host_tools
          BaseTool.descendants.select do |klass|
            klass.name && !klass.name.start_with?('Administrate::MCP::') && klass.instance_variable_get(:@name_value)
          end
        end

        private

        def load_host_tools
          Administrate::MCP.config.tool_paths.each do |path|
            Dir[File.join(path.to_s, '*.rb')].each { |file| require_dependency file }
          end
        end
      end
    end
  end
end
