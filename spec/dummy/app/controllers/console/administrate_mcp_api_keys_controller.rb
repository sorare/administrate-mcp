# frozen_string_literal: true

module Console
  # A host wiring the engine's API key console with nothing of its own.
  class AdministrateMcpApiKeysController < Console::ApplicationController
    include Administrate::MCP::ApiKeysAdmin
  end
end
