# frozen_string_literal: true

require_relative 'lib/administrate/mcp/version'

Gem::Specification.new do |spec|
  spec.name = 'administrate-mcp'
  spec.version = Administrate::MCP::VERSION
  spec.authors = ['Sorare']
  spec.email = ['engineering@sorare.com']

  spec.summary = 'Model Context Protocol server for Administrate dashboards'
  spec.description = 'Rails engine exposing Administrate dashboards over the Model Context Protocol, ' \
                     'with API key and OAuth 2.1 authentication.'
  spec.homepage = 'https://github.com/sorare/administrate-mcp'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir['{app,config,db,lib}/**/*', 'LICENSE.txt', 'README.md']
  spec.require_paths = ['lib']

  spec.add_dependency 'administrate', '>= 1.0.0.beta3'
  spec.add_dependency 'mcp', '~> 1.5'
  spec.add_dependency 'rails', '>= 8.1'
end
