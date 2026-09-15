# frozen_string_literal: true

RSpec.describe Administrate::MCP::OAuthController do
  let(:valid_code_challenge) { Base64.urlsafe_encode64(Digest::SHA256.digest('test_verifier'), padding: false) }

  describe 'GET /.well-known/oauth-protected-resource' do
    before { host! 'admin-mcp.example.com' }

    it 'returns resource metadata' do
      get '/.well-known/oauth-protected-resource'

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['authorization_servers']).to eq(['http://admin-mcp.example.com'])
      expect(response.parsed_body['bearer_methods_supported']).to eq(['header'])
    end
  end

  describe 'GET /.well-known/oauth-authorization-server' do
    before { host! 'admin-mcp.example.com' }

    it 'returns server metadata' do
      get '/.well-known/oauth-authorization-server'

      expect(response).to have_http_status(:ok)
      data = response.parsed_body
      expect(data['response_types_supported']).to eq(['code'])
      expect(data['grant_types_supported']).to include('authorization_code', 'refresh_token')
      expect(data['code_challenge_methods_supported']).to eq(['S256'])
      expect(data['token_endpoint_auth_methods_supported']).to eq(['none'])
      expect(data['authorization_endpoint']).to eq('https://admin.example.com/mcp/oauth/authorize')
      expect(data['token_endpoint']).to eq('http://admin-mcp.example.com/oauth/token')
      expect(data['registration_endpoint']).to eq('http://admin-mcp.example.com/oauth/register')
    end
  end

  describe 'POST /oauth/register' do
    before { host! 'admin-mcp.example.com' }

    def register(payload)
      post '/oauth/register', params: payload.to_json, headers: { 'Content-Type' => 'application/json' }
    end

    it 'creates an OAuth application' do
      register(client_name: 'My Client', redirect_uris: ['http://localhost:8080/callback'])

      expect(response).to have_http_status(:created)
      data = response.parsed_body
      expect(data['client_id']).to be_present
      expect(data['client_name']).to eq('My Client')
      expect(data['redirect_uris']).to eq(['http://localhost:8080/callback'])
    end

    context 'without a client_name' do
      before { Administrate::MCP.config.default_client_name = 'House Client' }
      after { Administrate::MCP.config.default_client_name = 'MCP Client' }

      it 'uses the configured default client name' do
        register(redirect_uris: ['http://localhost:8080/callback'])

        expect(response.parsed_body['client_name']).to eq('House Client')
      end
    end

    it 'rejects a registration without redirect_uris' do
      register(client_name: 'My Client')

      expect(response).to have_http_status(:bad_request)
    end

    it 'strips HTML from the client name' do
      register(client_name: '<script>alert("xss")</script>Evil Client',
               redirect_uris: ['http://localhost:8080/callback'])

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['client_name']).to eq('alert("xss")Evil Client')
    end

    it 'rejects a client name over 255 characters' do
      register(client_name: 'A' * 256, redirect_uris: ['http://localhost:8080/callback'])

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body['error']).to eq('invalid_client_metadata')
    end

    it 'rejects a non-loopback http redirect_uri' do
      register(client_name: 'My Client', redirect_uris: ['http://evil.com/callback'])

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body['error']).to eq('invalid_client_metadata')
    end

    it 'accepts an https redirect_uri' do
      register(client_name: 'My Client', redirect_uris: ['https://example.com/callback'])

      expect(response).to have_http_status(:created)
    end

    it 'rejects more than five redirect_uris' do
      register(client_name: 'My Client', redirect_uris: Array.new(6) { |i| "https://example.com/callback#{i}" })

      expect(response).to have_http_status(:bad_request)
    end

    it 'rejects a malformed redirect_uri' do
      register(client_name: 'My Client', redirect_uris: ['not a valid uri %%%'])

      expect(response).to have_http_status(:bad_request)
    end

    it 'accepts an IPv6 loopback redirect_uri and redirects the code back to it' do
      register(client_name: 'My Client', redirect_uris: ['http://[::1]:8080/cb'])

      expect(response).to have_http_status(:created)
    end

    it 'accepts loopback http redirect_uris' do
      register(client_name: 'My Client', redirect_uris: ['http://127.0.0.1:3000/callback'])

      expect(response).to have_http_status(:created)
    end
  end

  describe 'GET /mcp/oauth/authorize' do
    let(:admin) { create(:admin) }
    let!(:application) { create(:administrate_mcp_oauth_application) }
    let(:signed_in) { { 'X-Dummy-Admin' => admin.id } }

    before { host! 'admin.example.com' }

    it 'renders the authorization page' do
      get '/mcp/oauth/authorize',
          params: {
            client_id: application.client_id,
            redirect_uri: application.redirect_uris.first,
            response_type: 'code',
            code_challenge: valid_code_challenge,
            code_challenge_method: 'S256',
            state: 'test_state'
          },
          headers: signed_in

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(application.name)
      expect(response.body).to include('Authorize MCP access')
    end

    it 'shows the redirect destination and the requested scope' do
      get '/mcp/oauth/authorize',
          params: {
            client_id: application.client_id,
            redirect_uri: 'http://localhost:3000/callback',
            code_challenge: valid_code_challenge,
            scope: 'write'
          },
          headers: signed_in

      expect(response.body).to include('localhost', 'http://localhost:3000/callback', 'write')
    end

    it 'rejects an unknown client_id' do
      get '/mcp/oauth/authorize',
          params: { client_id: 'unknown', redirect_uri: 'http://localhost:3000/callback' },
          headers: signed_in

      expect(response).to have_http_status(:bad_request)
    end

    it 'rejects an unregistered redirect_uri' do
      get '/mcp/oauth/authorize',
          params: { client_id: application.client_id, redirect_uri: 'https://evil.com/callback' },
          headers: signed_in

      expect(response).to have_http_status(:bad_request)
    end

    it 'rejects a non-S256 code_challenge_method' do
      get '/mcp/oauth/authorize',
          params: {
            client_id: application.client_id,
            redirect_uri: application.redirect_uris.first,
            code_challenge: valid_code_challenge,
            code_challenge_method: 'plain'
          },
          headers: signed_in

      expect(response).to have_http_status(:bad_request)
      expect(response.body).to include('Unsupported code_challenge_method')
    end

    it 'rejects a malformed code_challenge' do
      get '/mcp/oauth/authorize',
          params: {
            client_id: application.client_id,
            redirect_uri: application.redirect_uris.first,
            code_challenge: 'tooshort'
          },
          headers: signed_in

      expect(response).to have_http_status(:bad_request)
      expect(response.body).to include('Invalid code_challenge format')
    end

    it 'renders without a code_challenge' do
      get '/mcp/oauth/authorize',
          params: { client_id: application.client_id, redirect_uri: application.redirect_uris.first },
          headers: signed_in

      expect(response).to have_http_status(:ok)
    end

    context 'when not authenticated' do
      it 'hands over to the host sign-in hook' do
        get '/mcp/oauth/authorize',
            params: { client_id: application.client_id, redirect_uri: application.redirect_uris.first }

        expect(response).to redirect_to('http://admin.example.com/admins/sign_in')
      end

      context 'without a sign-in hook' do
        before { Administrate::MCP.config.sign_in = nil }

        it 'returns 401' do
          get '/mcp/oauth/authorize',
              params: { client_id: application.client_id, redirect_uri: application.redirect_uris.first }

          expect(response).to have_http_status(:unauthorized)
        end
      end
    end
  end

  describe 'POST /mcp/oauth/authorize' do
    let(:admin) { create(:admin) }
    let!(:application) { create(:administrate_mcp_oauth_application) }
    let(:signed_in) { { 'X-Dummy-Admin' => admin.id } }

    before { host! 'admin.example.com' }

    it 'creates a grant and redirects with the code' do
      expect do
        post '/mcp/oauth/authorize',
             params: {
               client_id: application.client_id,
               redirect_uri: application.redirect_uris.first,
               code_challenge: valid_code_challenge,
               code_challenge_method: 'S256',
               state: 'test_state'
             },
             headers: signed_in
      end.to change(Administrate::MCP::OAuthAccessGrant, :count).by(1)

      expect(response).to have_http_status(:redirect)
      expect(response.location).to include('code=', 'state=test_state')
    end

    it 'redirects the code back to an IPv6 loopback callback' do
      application.update!(redirect_uris: ['http://[::1]:8080/cb'])

      post '/mcp/oauth/authorize',
           params: {
             client_id: application.client_id,
             redirect_uri: 'http://[::1]:8080/cb',
             code_challenge: valid_code_challenge,
             state: 'test_state'
           },
           headers: signed_in

      expect(response).to have_http_status(:redirect)
      expect(response.location).to start_with('http://[::1]:8080/cb?code=')
    end

    it 'refuses an unregistered redirect_uri without issuing a grant' do
      expect do
        post '/mcp/oauth/authorize',
             params: {
               client_id: application.client_id,
               redirect_uri: 'https://evil.com/callback',
               code_challenge: valid_code_challenge
             },
             headers: signed_in
      end.not_to change(Administrate::MCP::OAuthAccessGrant, :count)

      expect(response).to have_http_status(:bad_request)
      expect(response.body).to eq('Invalid redirect_uri')
    end

    context 'with forgery protection on, as in production' do
      around do |example|
        previous = ActionController::Base.allow_forgery_protection
        ActionController::Base.allow_forgery_protection = true
        example.run
        ActionController::Base.allow_forgery_protection = previous
      end

      it 'refuses a token-less approval' do
        expect do
          post '/mcp/oauth/authorize',
               params: {
                 client_id: application.client_id,
                 redirect_uri: application.redirect_uris.first,
                 code_challenge: valid_code_challenge
               },
               headers: signed_in
        end.to raise_error(ActionController::InvalidAuthenticityToken)
      end

      it 'still serves the token endpoint, which skips forgery protection' do
        host! 'admin-mcp.example.com'

        post '/oauth/token', params: { grant_type: 'client_credentials' }

        expect(response).to have_http_status(:bad_request)
      end
    end

    it 'redirects with an error when denied' do
      post '/mcp/oauth/authorize',
           params: {
             client_id: application.client_id,
             redirect_uri: application.redirect_uris.first,
             state: 'test_state',
             deny: '1'
           },
           headers: signed_in

      expect(response).to have_http_status(:redirect)
      expect(response.location).to include('error=access_denied')
    end
  end

  describe 'POST /oauth/token' do
    before { host! 'admin-mcp.example.com' }

    context 'with the authorization_code grant' do
      let(:verifier) { 'test_code_verifier_string' }
      let(:challenge) { Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false) }
      let!(:grant) { create(:administrate_mcp_oauth_access_grant, code_challenge: challenge) }

      it 'exchanges the code for tokens' do
        post '/oauth/token',
             params: {
               grant_type: 'authorization_code',
               code: grant.token,
               code_verifier: verifier,
               redirect_uri: grant.redirect_uri
             }

        expect(response).to have_http_status(:ok)
        data = response.parsed_body
        expect(data['access_token']).to be_present
        expect(data['refresh_token']).to be_present
        expect(data['token_type']).to eq('bearer')
        expect(data['expires_in']).to eq(Administrate::MCP::OAuthAccessToken::DEFAULT_EXPIRES_IN)
      end

      it 'revokes the grant after use' do
        post '/oauth/token', params: { grant_type: 'authorization_code', code: grant.token, code_verifier: verifier }

        expect(grant.reload).to be_revoked
      end

      it 'refuses a mismatched redirect_uri' do
        post '/oauth/token',
             params: {
               grant_type: 'authorization_code',
               code: grant.token,
               code_verifier: verifier,
               redirect_uri: 'https://evil.com/callback'
             }

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body).to include('error' => 'invalid_grant',
                                                'error_description' => 'redirect_uri mismatch')
      end

      it 'refuses an invalid code_verifier' do
        post '/oauth/token',
             params: { grant_type: 'authorization_code', code: grant.token, code_verifier: 'wrong_verifier' }

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body['error']).to eq('invalid_grant')
      end

      context 'with an expired grant' do
        let!(:grant) do
          create(:administrate_mcp_oauth_access_grant, code_challenge: challenge, created_at: 11.minutes.ago)
        end

        it 'refuses the exchange' do
          post '/oauth/token', params: { grant_type: 'authorization_code', code: grant.token, code_verifier: verifier }

          expect(response).to have_http_status(:bad_request)
        end
      end

      context 'with a revoked grant' do
        before { grant.revoke! }

        it 'refuses the exchange' do
          post '/oauth/token', params: { grant_type: 'authorization_code', code: grant.token, code_verifier: verifier }

          expect(response).to have_http_status(:bad_request)
        end
      end
    end

    context 'with the refresh_token grant' do
      let!(:access_token) { create(:administrate_mcp_oauth_access_token) }

      it 'issues a new token pair' do
        post '/oauth/token', params: { grant_type: 'refresh_token', refresh_token: access_token.refresh_token }

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['access_token']).to be_present
        expect(response.parsed_body['access_token']).not_to eq(access_token.token)
      end

      it 'revokes the old token' do
        post '/oauth/token', params: { grant_type: 'refresh_token', refresh_token: access_token.refresh_token }

        expect(access_token.reload).to be_revoked
      end

      context 'with a revoked refresh token' do
        before { access_token.revoke! }

        it 'refuses the exchange' do
          post '/oauth/token', params: { grant_type: 'refresh_token', refresh_token: access_token.refresh_token }

          expect(response).to have_http_status(:bad_request)
        end
      end
    end

    it 'refuses an unsupported grant type' do
      post '/oauth/token', params: { grant_type: 'client_credentials' }

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body['error']).to eq('unsupported_grant_type')
    end
  end
end
