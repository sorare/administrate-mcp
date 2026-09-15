# frozen_string_literal: true

Administrate::MCP::Engine.routes.draw do
  Administrate::MCP::Routes.draw_mcp_origin(self)
  Administrate::MCP::Routes.draw_admin_origin(self, path: '/oauth/authorize')
end
