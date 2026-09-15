# frozen_string_literal: true

RSpec.describe Administrate::MCP do
  it 'boots' do
    expect(described_class.config.server_name).to eq('dummy_admin')
  end
end
