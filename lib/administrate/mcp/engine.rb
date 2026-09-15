# frozen_string_literal: true

module Administrate
  module MCP
    # Mounts the models, controllers, tools and dashboard DSL into the host application.
    class Engine < ::Rails::Engine
      isolate_namespace Administrate::MCP

      initializer 'administrate_mcp.inflection', before: :set_autoload_paths do
        Rails.autoloaders.each { |loader| loader.inflector.inflect('mcp' => 'MCP') }
      end

      config.to_prepare do
        require 'administrate/mcp/dashboard_extension'
        Administrate::MCP::DashboardExtension.install!
        Administrate::MCP::DashboardRegistry.reset!
        Administrate::MCP::Actions.reset!
      end
    end
  end
end
