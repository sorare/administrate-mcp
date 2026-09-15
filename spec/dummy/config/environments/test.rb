# frozen_string_literal: true

Rails.application.configure do
  config.cache_classes = true
  config.eager_load = false
  config.action_controller.perform_caching = false
  config.action_dispatch.show_exceptions = :none
  config.active_support.deprecation = :stderr
end
