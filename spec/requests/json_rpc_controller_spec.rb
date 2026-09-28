# frozen_string_literal: true

RSpec.describe Administrate::MCP::JsonRpcController do
  let(:admin) { create(:admin, :full_access) }
  let(:token) { Administrate::MCP::ApiKey.generate_token }
  let!(:api_key) do
    create(
      :administrate_mcp_api_key,
      admin:,
      token_digest: Administrate::MCP::ApiKey.digest_token(token),
      token_prefix: token[0, 13]
    )
  end
  let(:headers) do
    {
      'Content-Type' => 'application/json',
      'Accept' => 'application/json, text/event-stream',
      'Authorization' => "Bearer #{token}"
    }
  end

  before { host! 'admin-mcp.example.com' }

  describe 'POST /' do
    context 'with a tools/list request' do
      it 'returns the list of available tools' do
        post '/', params: { jsonrpc: '2.0', method: 'tools/list', id: 1 }.to_json, headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.dig('result', 'tools').pluck('name')).to include('admin_resource_show')
      end
    end

    context 'without authentication' do
      it 'returns 401 with X-Auth-Error: unknown and error code -32001' do
        post '/', params: { jsonrpc: '2.0', method: 'tools/list', id: 1 }.to_json,
                  headers: headers.except('Authorization')

        expect(response).to have_http_status(:unauthorized)
        expect(response.headers['WWW-Authenticate']).to include('oauth-protected-resource')
        expect(response.headers['X-Auth-Error']).to eq('unknown')
        expect(response.parsed_body.dig('error', 'code')).to eq(-32_001)
      end
    end

    context 'with only a session cookie and no bearer token' do
      it 'never falls back to the session and returns 401' do
        post '/',
             params: { jsonrpc: '2.0', method: 'tools/list', id: 1 }.to_json,
             headers: headers.except('Authorization').merge('Cookie' => "_dummy_session=#{admin.id}",
                                                            'X-Dummy-Admin' => admin.id)

        expect(response).to have_http_status(:unauthorized)
        expect(response.headers['X-Auth-Error']).to eq('unknown')
      end
    end

    context 'with an invalid API key token' do
      it 'returns 401 with X-Auth-Error: api_key' do
        post '/',
             params: { jsonrpc: '2.0', method: 'tools/list', id: 1 }.to_json,
             headers: headers.merge('Authorization' => 'Bearer amcp_invalid')

        expect(response).to have_http_status(:unauthorized)
        expect(response.headers['X-Auth-Error']).to eq('api_key')
      end
    end

    context 'with an unknown OAuth token' do
      it 'returns 401 with X-Auth-Error: oauth' do
        post '/',
             params: { jsonrpc: '2.0', method: 'tools/list', id: 1 }.to_json,
             headers: headers.merge('Authorization' => 'Bearer unknown_oauth_token_value')

        expect(response).to have_http_status(:unauthorized)
        expect(response.headers['X-Auth-Error']).to eq('oauth')
        expect(response.parsed_body.dig('error', 'code')).to eq(-32_001)
      end
    end

    context 'with a valid OAuth access token' do
      let(:oauth_token) { create(:administrate_mcp_oauth_access_token, admin:) }

      it 'authenticates successfully' do
        post '/',
             params: { jsonrpc: '2.0', method: 'tools/list', id: 1 }.to_json,
             headers: headers.merge('Authorization' => "Bearer #{oauth_token.plaintext_token}")

        expect(response).to have_http_status(:ok)
      end
    end

    context 'with an expired OAuth access token' do
      let(:oauth_token) { create(:administrate_mcp_oauth_access_token, admin:, created_at: 2.weeks.ago) }

      it 'returns 401 with X-Auth-Error: oauth' do
        post '/',
             params: { jsonrpc: '2.0', method: 'tools/list', id: 1 }.to_json,
             headers: headers.merge('Authorization' => "Bearer #{oauth_token.plaintext_token}")

        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body.dig('error', 'message')).to eq('Token has expired')
      end
    end

    context 'with a revoked OAuth access token' do
      let(:oauth_token) { create(:administrate_mcp_oauth_access_token, admin:, revoked_at: Time.current) }

      it 'returns 401 with X-Auth-Error: oauth' do
        post '/',
             params: { jsonrpc: '2.0', method: 'tools/list', id: 1 }.to_json,
             headers: headers.merge('Authorization' => "Bearer #{oauth_token.plaintext_token}")

        expect(response).to have_http_status(:unauthorized)
        expect(response.headers['X-Auth-Error']).to eq('oauth')
        expect(response.parsed_body.dig('error', 'message')).to eq('Token has been revoked')
      end
    end

    context 'with an identity fallback configured' do
      before do
        Administrate::MCP.config.identity_fallback = lambda do |request|
          id = request.headers['X-Asserted-Admin']
          id && Administrate::MCP::Authentication::Identity.new(admin: Admin.find_by(id:), scopes: [])
        end
      end

      it 'authenticates a request that carries no Authorization header' do
        post '/',
             params: { jsonrpc: '2.0', method: 'tools/list', id: 1 }.to_json,
             headers: headers.except('Authorization').merge('X-Asserted-Admin' => admin.id)

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.dig('result', 'tools').pluck('name')).to include('admin_resource_show')
      end

      it 'still refuses when the fallback asserts nothing' do
        post '/', params: { jsonrpc: '2.0', method: 'tools/list', id: 1 }.to_json,
                  headers: headers.except('Authorization')

        expect(response).to have_http_status(:unauthorized)
        expect(response.headers['X-Auth-Error']).to eq('unknown')
      end

      context 'when the fallback recognises the caller but finds no admin' do
        before do
          Administrate::MCP.config.identity_fallback = lambda do |_request|
            raise Administrate::MCP::Authentication::ExternalIdentityError.new(
              'No admin account for this identity',
              auth_error_type: 'cloudflare_access'
            )
          end
        end

        it 'returns 401 with the host error type and code -32001' do
          post '/', params: { jsonrpc: '2.0', method: 'tools/list', id: 1 }.to_json,
                    headers: headers.except('Authorization')

          expect(response).to have_http_status(:unauthorized)
          expect(response.headers['X-Auth-Error']).to eq('cloudflare_access')
          expect(response.parsed_body.dig('error', 'code')).to eq(-32_001)
          expect(response.parsed_body.dig('error', 'message')).to eq('No admin account for this identity')
        end
      end
    end

    context 'when the host reports the admin as no longer active' do
      before { Administrate::MCP.config.admin_active = ->(_admin) { false } }

      it 'returns 401 with X-Auth-Error: inactive_admin for an API key' do
        post '/', params: { jsonrpc: '2.0', method: 'tools/list', id: 1 }.to_json, headers: headers

        expect(response).to have_http_status(:unauthorized)
        expect(response.headers['X-Auth-Error']).to eq('inactive_admin')
        expect(response.parsed_body.dig('error', 'code')).to eq(-32_001)
      end

      it 'returns 401 with X-Auth-Error: inactive_admin for an OAuth token' do
        oauth_token = create(:administrate_mcp_oauth_access_token, admin:)

        post '/',
             params: { jsonrpc: '2.0', method: 'tools/list', id: 1 }.to_json,
             headers: headers.merge('Authorization' => "Bearer #{oauth_token.plaintext_token}")

        expect(response).to have_http_status(:unauthorized)
        expect(response.headers['X-Auth-Error']).to eq('inactive_admin')
      end
    end

    context 'with a revoked API key' do
      before { api_key.revoke! }

      it 'returns 401 with X-Auth-Error: api_key' do
        post '/', params: { jsonrpc: '2.0', method: 'tools/list', id: 1 }.to_json, headers: headers

        expect(response).to have_http_status(:unauthorized)
        expect(response.headers['X-Auth-Error']).to eq('api_key')
      end
    end

    context 'with a tools/call for report_mcp_improvement' do
      let(:body) do
        {
          jsonrpc: '2.0',
          method: 'tools/call',
          id: 2,
          params: {
            name: 'report_mcp_improvement',
            arguments: {
              category: 'description',
              suggestion: 'Misleading description on widgets'
            }
          }
        }.to_json
      end

      it 'creates feedback and returns success' do
        expect { post('/', params: body, headers:) }.to change(Administrate::MCP::Feedback, :count).by(1)

        expect(response).to have_http_status(:ok)
        content = JSON.parse(response.parsed_body.dig('result', 'content', 0, 'text'))
        expect(content['status']).to eq('created')
      end

      context 'with missing required params' do
        let(:body) do
          {
            jsonrpc: '2.0',
            method: 'tools/call',
            id: 2,
            params: {
              name: 'report_mcp_improvement',
              arguments: {
                category: 'description'
              }
            }
          }.to_json
        end

        it 'returns an error response' do
          expect { post('/', params: body, headers:) }.not_to change(Administrate::MCP::Feedback, :count)

          expect(response).to have_http_status(:ok)
          expect(response.parsed_body.dig('result', 'isError')).to be(true)
        end
      end
    end

    describe 'resource errors on the admin_resource tools' do
      def call_tool(name, arguments, id: 5)
        body = { jsonrpc: '2.0', method: 'tools/call', id:, params: { name:, arguments: } }.to_json
        post '/', params: body, headers: headers
      end

      {
        'admin_resource_list' => { verb: 'list', arguments: {} },
        'admin_resource_show' => { verb: 'show', arguments: { id: 'any' } },
        'admin_resource_list_resources' => { verb: 'list', arguments: {} }
      }.each do |tool, spec|
        context "with #{tool}" do
          it 'returns an unknown resource name as a tool error, not a 403' do
            call_tool(tool, spec[:arguments].merge(resource: 'widgit'))

            expect(response).to have_http_status(:ok)
            expect(response.headers['X-Auth-Error']).to be_nil
            expect(response.parsed_body.dig('result', 'isError')).to be(true)
            expect(response.parsed_body.dig('result', 'content', 0, 'text')).to eq(
              'Unknown resource: widgit. This name is not registered. Closest registered names: widget'
            )
          end

          it 'returns a resource the caller cannot read as a tool error, not a 403' do
            Administrate::MCP.config.authorization = Administrate::MCP::Authorization::Pundit.new
            stub_const(
              'WidgetPolicy',
              Class.new do
                def initialize(admin, _record) = @admin = admin
                def index? = false
                def show? = false
              end
            )

            call_tool(tool, spec[:arguments].merge(resource: 'widget'))

            expect(response).to have_http_status(:ok)
            expect(response.headers['X-Auth-Error']).to be_nil
            expect(response.parsed_body.dig('result', 'isError')).to be(true)
            expect(response.parsed_body.dig('result', 'content', 0, 'text')).to eq(
              "Resource `widget` exists but you are not authorized to #{spec[:verb]} it."
            )
          end

          # Current behaviour, not a contract: https://github.com/sorare/administrate-mcp/issues/11 proposes
          # a step-up WWW-Authenticate header for a missing scope and a tool error for a missing role.
          it 'currently answers a tool-level refusal with 403, X-Auth-Error: forbidden and code -32003' do
            tool_class = Administrate::MCP::ServerBuilder.built_in_tools.find { |klass| klass.name_value == tool }
            allow(tool_class).to receive(:required_scopes).and_return([:write])

            call_tool(tool, spec[:arguments].merge(resource: 'widget'))

            expect(response).to have_http_status(:forbidden)
            expect(response.headers['X-Auth-Error']).to eq('forbidden')
            expect(response.parsed_body.dig('error', 'code')).to eq(-32_003)
            expect(response.parsed_body.dig('error', 'message')).to eq('Missing required scope(s): write')
            expect(response.parsed_body['id']).to eq(5)
          end
        end
      end

      it 'currently answers a tool-level refusal with 403 when the call carries a params _meta object' do
        allow(Administrate::MCP::Tools::AdminResourceList).to receive(:required_scopes).and_return([:write])
        body = {
          jsonrpc: '2.0',
          method: 'tools/call',
          id: 6,
          params: {
            name: 'admin_resource_list',
            arguments: {
              resource: 'widget'
            },
            _meta: {
              progressToken: 'token'
            }
          }
        }.to_json
        post '/', params: body, headers: headers

        expect(response).to have_http_status(:forbidden)
        expect(response.parsed_body.dig('error', 'code')).to eq(-32_003)
      end
    end

    context 'without the required Accept header' do
      it 'returns 406' do
        post '/',
             params: { jsonrpc: '2.0', method: 'tools/list', id: 1 }.to_json,
             headers: headers.merge('Accept' => 'text/plain')

        expect(response).to have_http_status(:not_acceptable)
      end
    end

    context 'with an initialize handshake' do
      it 'negotiates the session lifecycle and reports the configured server name' do
        body = {
          jsonrpc: '2.0',
          method: 'initialize',
          id: 1,
          params: {
            protocolVersion: '2025-06-18',
            capabilities: {},
            clientInfo: {
              name: 'rspec',
              version: '1.0'
            }
          }
        }.to_json
        post '/', params: body, headers: headers

        expect(response).to have_http_status(:ok)
        result = response.parsed_body['result']
        expect(result['protocolVersion']).to eq('2025-06-18')
        expect(result.dig('serverInfo', 'name')).to eq('dummy_admin')
      end
    end
  end

  describe 'POST / on the 2026-07-28 modern lifecycle' do
    let(:protocol_version) { '2026-07-28' }
    let(:rpc_method) { 'tools/list' }
    let(:rpc_id) { 1 }
    let(:rpc_params) { {} }
    let(:tool_name) { nil }
    let(:method_header) { rpc_method }
    let(:envelope) do
      {
        'io.modelcontextprotocol/protocolVersion' => protocol_version,
        'io.modelcontextprotocol/clientInfo' => {
          name: 'rspec',
          version: '1.0'
        },
        'io.modelcontextprotocol/clientCapabilities' => {}
      }
    end
    let(:modern_headers) do
      headers.merge(
        'MCP-Protocol-Version' => protocol_version,
        'Mcp-Method' => method_header,
        'Mcp-Name' => tool_name
      ).compact
    end
    let(:body) { { jsonrpc: '2.0', method: rpc_method, id: rpc_id, params: rpc_params.merge(_meta: envelope) }.to_json }

    context 'with server/discover' do
      let(:rpc_method) { 'server/discover' }

      it 'advertises the modern version, the tools capability and the server identity' do
        post '/', params: body, headers: modern_headers

        expect(response).to have_http_status(:ok)
        result = response.parsed_body['result']
        expect(result['resultType']).to eq('complete')
        expect(result['supportedVersions']).to eq([protocol_version])
        expect(result['capabilities']).to have_key('tools')
        expect(result.dig('_meta', 'io.modelcontextprotocol/serverInfo', 'name')).to eq('dummy_admin')
      end

      it 'does not advertise list-change notifications it cannot deliver' do
        post '/', params: body, headers: modern_headers

        expect(response.parsed_body.dig('result', 'capabilities', 'tools')).not_to have_key('listChanged')
      end
    end

    context 'with tools/list' do
      it 'returns the result discriminator and the cache hints' do
        post '/', params: body, headers: modern_headers

        expect(response).to have_http_status(:ok)
        result = response.parsed_body['result']
        expect(result['resultType']).to eq('complete')
        expect(result['ttlMs']).to eq(0)
        expect(result['cacheScope']).to eq('private')
        expect(result['tools'].pluck('name')).to include('admin_resource_show')
      end

      it 'returns the tools in the same order on every call' do
        post '/', params: body, headers: modern_headers
        first_call = response.parsed_body.dig('result', 'tools').pluck('name')

        post '/', params: body, headers: modern_headers

        expect(response.parsed_body.dig('result', 'tools').pluck('name')).to eq(first_call)
      end
    end

    context 'with tools/call' do
      let(:rpc_method) { 'tools/call' }
      let(:tool_name) { 'report_mcp_improvement' }
      let(:rpc_params) do
        { name: tool_name, arguments: { category: 'description', suggestion: 'Misleading description on widgets' } }
      end

      it 'runs the tool' do
        expect { post('/', params: body, headers: modern_headers) }
          .to change(Administrate::MCP::Feedback, :count).by(1)

        expect(response).to have_http_status(:ok)
        result = response.parsed_body['result']
        expect(result['resultType']).to eq('complete')
        expect(JSON.parse(result.dig('content', 0, 'text'))['status']).to eq('created')
      end
    end

    context 'with subscriptions/listen' do
      let(:rpc_method) { 'subscriptions/listen' }
      let(:rpc_params) { { notifications: { toolsListChanged: true } } }

      it 'answers the method as unimplemented instead of opening a stream' do
        post '/', params: body, headers: modern_headers

        expect(response).to have_http_status(:not_found)
        expect(response.media_type).to eq('application/json')
        expect(response.parsed_body.dig('error', 'code')).to eq(-32_601)
        expect(response.parsed_body['id']).to eq(rpc_id)
      end
    end

    context 'without the Mcp-Method header' do
      let(:method_header) { nil }

      it 'returns 400 with error code -32020' do
        post '/', params: body, headers: modern_headers

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body.dig('error', 'code')).to eq(-32_020)
        expect(response.parsed_body.dig('error', 'message')).to include('Mcp-Method header is required')
      end
    end

    # Current behaviour, not a contract: see https://github.com/sorare/administrate-mcp/issues/11.
    context 'with a tool call a tool-level gate refuses' do
      let(:rpc_method) { 'tools/call' }
      let(:rpc_id) { 5 }
      let(:tool_name) { 'admin_resource_list' }
      let(:rpc_params) { { name: tool_name, arguments: { resource: 'widget' } } }

      before { allow(Administrate::MCP::Tools::AdminResourceList).to receive(:required_scopes).and_return([:write]) }

      it 'currently returns 403 with X-Auth-Error: forbidden and error code -32003' do
        post '/', params: body, headers: modern_headers

        expect(response).to have_http_status(:forbidden)
        expect(response.headers['X-Auth-Error']).to eq('forbidden')
        expect(response.parsed_body.dig('error', 'code')).to eq(-32_003)
        expect(response.parsed_body.dig('error', 'message')).to eq('Missing required scope(s): write')
        expect(response.parsed_body['id']).to eq(5)
      end
    end
  end

  describe 'GET /' do
    it 'returns 405 in stateless mode' do
      get '/', headers: { 'Accept' => 'text/event-stream', 'Authorization' => "Bearer #{token}" }

      expect(response).to have_http_status(:method_not_allowed)
    end
  end

  describe 'DELETE /' do
    it 'returns 200' do
      delete '/', headers: { 'Authorization' => "Bearer #{token}" }

      expect(response).to have_http_status(:ok)
    end
  end
end
