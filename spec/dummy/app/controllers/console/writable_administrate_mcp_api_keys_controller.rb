# frozen_string_literal: true

module Console
  # A host that lets its admins mint write-enabled keys, which is the one decision the engine
  # refuses to make for it.
  class WritableAdministrateMcpApiKeysController < Console::AdministrateMcpApiKeysController
    private

    def mcp_write_access_allowed?
      true
    end
  end
end
