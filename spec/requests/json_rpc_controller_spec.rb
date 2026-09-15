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
             headers: headers.merge('Authorization' => "Bearer #{oauth_token.token}")

        expect(response).to have_http_status(:ok)
      end
    end

    context 'with an expired OAuth access token' do
      let(:oauth_token) { create(:administrate_mcp_oauth_access_token, admin:, created_at: 2.weeks.ago) }

      it 'returns 401 with X-Auth-Error: oauth' do
        post '/',
             params: { jsonrpc: '2.0', method: 'tools/list', id: 1 }.to_json,
             headers: headers.merge('Authorization' => "Bearer #{oauth_token.token}")

        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body.dig('error', 'message')).to eq('Token has expired')
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

    context 'with a tool call the admin is not authorized for' do
      it 'returns 403 with X-Auth-Error: forbidden and error code -32003' do
        body = {
          jsonrpc: '2.0',
          method: 'tools/call',
          id: 5,
          params: {
            name: 'admin_resource_list',
            arguments: {
              resource: 'nonexistent_resource'
            }
          }
        }.to_json
        post '/', params: body, headers: headers

        expect(response).to have_http_status(:forbidden)
        expect(response.headers['X-Auth-Error']).to eq('forbidden')
        expect(response.parsed_body.dig('error', 'code')).to eq(-32_003)
        expect(response.parsed_body.dig('error', 'message')).to include('Unknown resource')
        expect(response.parsed_body['id']).to eq(5)
      end

      it 'still returns 403 when the call carries a params _meta object' do
        body = {
          jsonrpc: '2.0',
          method: 'tools/call',
          id: 6,
          params: {
            name: 'admin_resource_list',
            arguments: {
              resource: 'nonexistent_resource'
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
