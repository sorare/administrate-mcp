# frozen_string_literal: true

require 'administrate/mcp/authorization/base'

module Administrate
  module MCP
    module Authorization
      # Grants every action to every authenticated admin. The default when the host has no policies.
      class Permissive < Base
      end
    end
  end
end
