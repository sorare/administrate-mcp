# frozen_string_literal: true

RSpec.describe Administrate::MCP::Engine do
  it 'names itself so migrations install under administrate_mcp' do
    expect(described_class.engine_name).to eq('administrate_mcp')
  end

  it 'prefixes its tables' do
    expect(Administrate::MCP.table_name_prefix).to eq('administrate_mcp_')
    expect(Administrate::MCP::ApiKey.table_name).to eq('administrate_mcp_api_keys')
  end

  it 'draws a routes set of its own, for hosts that serve everything on one origin' do
    paths = described_class.routes.routes.map { |route| route.path.spec.to_s }

    expect(paths).to include(
      '/.well-known/oauth-protected-resource(.:format)',
      '/.well-known/oauth-authorization-server(.:format)',
      '/oauth/register(.:format)',
      '/oauth/token(.:format)',
      '/oauth/authorize(.:format)',
      '/'
    )
  end

  it 'installs the MCP inflection on the autoloader rather than globally' do
    expect(Rails.autoloaders.main.inflector.camelize('mcp', nil)).to eq('MCP')
    expect(ActiveSupport::Inflector.inflections.acronyms).not_to include('mcp')
  end

  it 'adds the dashboard DSL to every dashboard' do
    expect(Administrate::BaseDashboard).to respond_to(:mcp_action)
    expect(Administrate::BaseDashboard.mcp_action_specs).to eq([])
  end
end
