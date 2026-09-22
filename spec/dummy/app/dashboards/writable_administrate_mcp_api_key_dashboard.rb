# frozen_string_literal: true

# Administrate names a dashboard after the controller, so the second console in this dummy needs its
# own. It changes nothing: what it exercises is the write-access decision, not the columns.
class WritableAdministrateMcpApiKeyDashboard < AdministrateMcpApiKeyDashboard
  MCP_EXPOSED = false
end
