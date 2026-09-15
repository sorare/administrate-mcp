# frozen_string_literal: true

require_relative 'boot'

require 'rails'
require 'active_record/railtie'
require 'action_controller/railtie'
require 'action_view/railtie'
require 'sprockets/railtie'

require 'kaminari'
require 'administrate'
require 'pundit'
require 'sidekiq'
require 'sidekiq/api'
require 'administrate/mcp'

module Dummy
  class Application < Rails::Application
    config.load_defaults 8.1
    config.root = File.expand_path('..', __dir__)
    config.eager_load = false
    config.consider_all_requests_local = true
    config.action_dispatch.show_exceptions = :none
    config.secret_key_base = 'dummy-secret-key-base-for-specs-only'
    config.hosts.clear
    config.logger = Logger.new(File.expand_path('../log/test.log', __dir__))
  end
end
