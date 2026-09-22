# frozen_string_literal: true

# What a host writes for the console: the engine's columns under the name this host's inflections
# give the file. Declared MCP_EXPOSED = false because the console is not a protocol resource; the
# dashboard under app/dashboards/administrate_mcp/ is the one this dummy publishes.
class AdministrateMcpApiKeyDashboard < Administrate::MCP::ApiKeyDashboard
  MCP_EXPOSED = false
end
