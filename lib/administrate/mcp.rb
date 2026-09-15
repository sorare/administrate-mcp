# frozen_string_literal: true

require 'mcp'
require 'administrate'

require 'administrate/mcp/version'
require 'administrate/mcp/errors'
require 'administrate/mcp/loopback_uri'
require 'administrate/mcp/configuration'
require 'administrate/mcp/routes'
require 'administrate/mcp/engine'

module Administrate
  # Model Context Protocol server for Administrate dashboards.
  module MCP
    def self.table_name_prefix
      'administrate_mcp_'
    end

    def self.config
      @config ||= Configuration.new
    end

    def self.configure
      yield(config)
      config
    end

    def self.reset_config!
      @config = Configuration.new
    end
  end
end
