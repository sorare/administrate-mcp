# frozen_string_literal: true

RSpec.describe 'engine model names' do
  it 'keeps the namespace despite isolate_namespace, so host resources are not shadowed' do
    name = Administrate::MCP::ApiKey.model_name

    expect(name.route_key).to eq('administrate_mcp_api_keys')
    expect(name.singular_route_key).to eq('administrate_mcp_api_key')
    expect(name.param_key).to eq('administrate_mcp_api_key')
  end

  it 'does the same for feedbacks' do
    name = Administrate::MCP::Feedback.model_name

    expect(name.route_key).to eq('administrate_mcp_feedbacks')
    expect(name.param_key).to eq('administrate_mcp_feedback')
  end

  it 'namespaces every engine record' do
    [
      Administrate::MCP::OAuthApplication,
      Administrate::MCP::OAuthAccessGrant,
      Administrate::MCP::OAuthAccessToken
    ].each do |klass|
      expect(klass.model_name.route_key).to start_with('administrate_mcp_')
    end
  end
end
