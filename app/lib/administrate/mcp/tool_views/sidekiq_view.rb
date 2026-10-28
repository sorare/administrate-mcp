# frozen_string_literal: true

module Administrate
  module MCP
    module ToolViews
      # Renders sidekiq_stats and sidekiq_retries results as counts per job class and a retry list,
      # with a refresh button.
      class SidekiqView < ToolView
        view_name 'sidekiq'
        title 'Sidekiq'
        description 'Job counts and retries from a sidekiq_stats or sidekiq_retries call.'
        script runtime_path('sidekiq.js')
        stylesheet runtime_path('sidekiq.css')
      end
    end
  end
end
