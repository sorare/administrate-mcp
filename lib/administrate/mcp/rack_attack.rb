# frozen_string_literal: true

module Administrate
  module MCP
    # Recommended Rack::Attack throttles for the OAuth endpoints. The gem does not depend on
    # rack-attack: call this from the host's own Rack::Attack initializer.
    module RackAttack
      THROTTLES = [
        { name: 'mcp_oauth/register/ip', limit: 5, period: 60, method: 'POST', path: '/oauth/register' },
        { name: 'mcp_oauth/register/ip-day', limit: 50, period: 86_400, method: 'POST', path: '/oauth/register' },
        { name: 'mcp_oauth/token/ip', limit: 10, period: 60, method: 'POST', path: '/oauth/token' }
      ].freeze

      AUTHORIZE_THROTTLE = {
        name: 'mcp_oauth/authorize/ip',
        limit: 20,
        period: 60,
        method: 'GET',
        path: Routes::AUTHORIZE_PATH
      }.freeze

      # `host` is the MCP origin host, or a substring of it; the authorize throttle applies on the
      # admin origin and is not host-scoped.
      def self.throttles(host:)
        THROTTLES.each do |rule|
          ::Rack::Attack.throttle(rule[:name], limit: rule[:limit], period: rule[:period]) do |req|
            req.remote_ip if req.request_method == rule[:method] && req.path == rule[:path] &&
                             req.host.include?(host)
          end
        end

        rule = AUTHORIZE_THROTTLE
        ::Rack::Attack.throttle(rule[:name], limit: rule[:limit], period: rule[:period]) do |req|
          req.remote_ip if req.request_method == rule[:method] && req.path == rule[:path]
        end
      end
    end
  end
end
