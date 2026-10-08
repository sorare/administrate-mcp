# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

gem 'database_cleaner-active_record'
# json 3 changed JSON.parse's arity and Rails 8.1 still calls the two-argument form when it parses a
# JSON request body, so every JSON POST in the specs raises. Development only; the gemspec is silent.
gem 'json', '~> 3.0'

gem 'factory_bot_rails'
gem 'pg'
gem 'puma'
gem 'pundit'
gem 'rspec-rails'
gem 'rubocop'
gem 'rubocop-rails'
gem 'rubocop-rspec'
gem 'shoulda-matchers'
gem 'sidekiq'
gem 'sprockets-rails'
gem 'webmock'
