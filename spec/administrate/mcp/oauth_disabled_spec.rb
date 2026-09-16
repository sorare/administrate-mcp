# frozen_string_literal: true

RSpec.describe 'a host that runs without the engine OAuth server' do
  let(:oauth_tables) do
    %w[
      administrate_mcp_oauth_access_tokens
      administrate_mcp_oauth_access_grants
      administrate_mcp_oauth_applications
    ]
  end
  let(:admin) { create(:admin, :full_access) }
  let(:token) { Administrate::MCP::ApiKey.generate_token }

  before do
    create(
      :administrate_mcp_api_key,
      admin:,
      token_digest: Administrate::MCP::ApiKey.digest_token(token),
      token_prefix: token[0, 13]
    )
  end

  # The tables go away entirely: a host that never ran the OAuth migration must still boot, eager
  # load and serve every request, so nothing may so much as look at those models.
  around do |example|
    connection = ActiveRecord::Base.connection
    oauth_tables.each { |table| connection.drop_table(table, if_exists: true, force: :cascade) }
    connection.schema_cache.clear!
    Administrate::MCP.config.oauth = false

    example.run
  ensure
    restore_oauth_tables
  end

  def restore_oauth_tables
    context = ActiveRecord::MigrationContext.new(File.expand_path('../../../db/migrate', __dir__))
    version = context.migrations.find { |migration| migration.name.include?('AuthorizationTables') }.version
    ActiveRecord::Base.connection.execute("DELETE FROM schema_migrations WHERE version = '#{version}'")
    ActiveRecord::Migration.suppress_messages { context.migrate }
    ActiveRecord::Base.connection.schema_cache.clear!
  end

  def request_with(headers)
    instance_double(ActionDispatch::Request, headers:)
  end

  it 'eager loads without touching the missing tables' do
    expect { Rails.application.eager_load! }.not_to raise_error
  end

  it 'authenticates an API key' do
    identity = Administrate::MCP::Authentication.authenticate!(request_with('Authorization' => "Bearer #{token}"))

    expect(identity.admin).to eq(admin)
  end

  it 'treats a bearer token it cannot recognise as an invalid token, without querying the table' do
    request = request_with('Authorization' => 'Bearer some-oauth-looking-token')

    expect { Administrate::MCP::Authentication.authenticate!(request) }.to raise_error(
      Administrate::MCP::Authentication::OAuthTokenError,
      'Invalid token'
    )
  end

  it 'still reports a missing header as such' do
    expect { Administrate::MCP::Authentication.authenticate!(request_with({})) }.to raise_error(
      Administrate::MCP::Authentication::Error,
      'Missing Authorization header'
    )
  end

  it 'hands an unrecognised bearer to the identity fallback' do
    fallback_identity = Administrate::MCP::Authentication::Identity.new(admin:, scopes: ['write'])
    Administrate::MCP.config.identity_fallback = ->(_request) { fallback_identity }

    identity = Administrate::MCP::Authentication.authenticate!(request_with('Authorization' => 'Bearer edge-token'))

    expect(identity).to eq(fallback_identity)
  end

  describe 'the routes' do
    def drawn_paths(&)
      set = ActionDispatch::Routing::RouteSet.new
      set.draw(&)
      set.routes.map { |route| route.path.spec.to_s }
    end

    it 'draws only the JSON-RPC endpoint on the MCP origin' do
      paths = drawn_paths { Administrate::MCP::Routes.draw_mcp_origin(self) }

      expect(paths).to eq(['/'])
    end

    it 'draws nothing on the admin origin' do
      expect(drawn_paths { Administrate::MCP::Routes.draw_admin_origin(self) }).to be_empty
    end
  end
end
