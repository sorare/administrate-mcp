# frozen_string_literal: true

ENV['RAILS_ENV'] = 'test'

require File.expand_path('dummy/config/environment', __dir__)

require 'rspec/rails'
require 'factory_bot_rails'
require 'shoulda-matchers'
require 'database_cleaner/active_record'

Dir[File.expand_path('support/**/*.rb', __dir__)].each { |f| require f }

# Before any spec file references an engine constant: the models read `admin_class_name` when they
# are autoloaded, exactly as a host application configures the engine from an initializer.
ConfigureDummy.apply!

ActiveRecord::Schema.verbose = false
ActiveRecord::Migration.verbose = false

load File.expand_path('dummy/db/schema.rb', __dir__)
ActiveRecord::MigrationContext.new(File.expand_path('../db/migrate', __dir__)).migrate

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.mock_with(:rspec) { |c| c.verify_partial_doubles = true }
  config.include FactoryBot::Syntax::Methods
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  config.before(:suite) { DatabaseCleaner.strategy = :truncation }
  config.around { |example| DatabaseCleaner.cleaning { example.run } }
  config.after { Administrate::MCP.reset_config! && ConfigureDummy.apply! }
end
