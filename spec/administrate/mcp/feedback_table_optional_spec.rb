# frozen_string_literal: true

RSpec.describe 'a host that never turns on feedback persistence' do
  let(:admin) { create(:admin, :full_access) }

  # The table goes away entirely: a host that never runs the feedbacks migration, or never wants
  # the row stored, must still boot, eager load and serve the report_mcp_improvement tool, so
  # nothing on that path may so much as look at the table.
  around do |example|
    connection = ActiveRecord::Base.connection
    connection.drop_table(:administrate_mcp_feedbacks, if_exists: true, force: :cascade)
    connection.schema_cache.clear!
    Administrate::MCP::Feedback.reset_column_information
    Administrate::MCP.config.persist_feedback = false

    example.run
  ensure
    restore_feedbacks_table
  end

  def restore_feedbacks_table
    context = ActiveRecord::MigrationContext.new(File.expand_path('../../../db/migrate', __dir__))
    version = context.migrations.find { |migration| migration.name.include?('Feedbacks') }.version
    ActiveRecord::Base.connection.execute("DELETE FROM schema_migrations WHERE version = '#{version}'")
    ActiveRecord::Migration.suppress_messages { context.migrate }
    ActiveRecord::Base.connection.schema_cache.clear!
    Administrate::MCP::Feedback.reset_column_information
  end

  it 'eager loads without touching the missing table' do
    expect { Rails.application.eager_load! }.not_to raise_error
  end

  it 'runs the report_mcp_improvement tool without touching the table' do
    result = Administrate::MCP::Tools::ReportImprovement.call(
      server_context: { admin: }, category: 'description', suggestion: 'Unclear'
    )

    expect(JSON.parse(result.content.first[:text])).to eq('status' => 'created')
  end

  it 'still validates a bad category through ReportImprovement' do
    result = Administrate::MCP::ReportImprovement.call(admin:, category: 'nope', suggestion: 'Unclear')

    expect(result).not_to be_success
    expect(result.errors.first).to include('category must be one of')
  end

  it 'discovers the built-in tools with the tool enabled, none of it touching the table' do
    names = Administrate::MCP::ServerBuilder.discover_tools({ admin:, scopes: [] }).map(&:name_value)

    expect(names).to include('report_mcp_improvement')
  end

  it 'discovers the built-in tools with the tool disabled, none of it touching the table' do
    Administrate::MCP.config.feedback_tool = false

    names = Administrate::MCP::ServerBuilder.discover_tools({ admin:, scopes: [] }).map(&:name_value)

    expect(names).not_to include('report_mcp_improvement')
  end
end
