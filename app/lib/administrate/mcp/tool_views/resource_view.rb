# frozen_string_literal: true

module Administrate
  module MCP
    module ToolViews
      # Renders admin_resource_list and admin_resource_show results as a table and a record page,
      # and lets the viewer page, sort, search and follow associations without a model round trip.
      class ResourceView < ToolView
        view_name 'resource'
        title 'Admin records'
        description 'Browse the records an admin_resource_list or admin_resource_show call returned.'
        script runtime_path('resource.js')
        stylesheet runtime_path('resource.css')
      end
    end
  end
end
