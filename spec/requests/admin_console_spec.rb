# frozen_string_literal: true

RSpec.describe 'the admin console a host includes', type: :request do
  let(:admin) { create(:admin, :full_access) }
  let(:headers) { { 'X-Dummy-Admin' => admin.id.to_s, 'HOST' => 'admin.example.com' } }

  def create_key(name: 'CI', write_access: nil, path: '/console/administrate_mcp_api_keys')
    params = { administrate_mcp_api_key: { name:, write_access: }.compact }
    post path, params:, headers: headers
  end

  describe 'creating a key' do
    it 'shows the token once and stores only its digest' do
      expect { create_key }.to change(Administrate::MCP::ApiKey, :count).by(1)

      key = Administrate::MCP::ApiKey.last
      token = flash[:notice][/amcp_\h+/]

      expect(response).to redirect_to('/console/administrate_mcp_api_keys')
      expect(token).to be_present
      expect(key.token_digest).to eq(Administrate::MCP::ApiKey.digest_token(token))
      expect(key.attributes.values.map(&:to_s)).not_to include(token)
      expect(key.admin).to eq(admin)
      expect(key.token_prefix).to eq(token[0, 13])
    end

    it 'names an unnamed key rather than refusing it' do
      create_key(name: '')

      expect(Administrate::MCP::ApiKey.last.name).to eq('Unnamed key')
    end

    it "refuses write access, which is the host's decision to grant" do
      create_key(write_access: '1')

      expect(response).to have_http_status(:unprocessable_content)
      expect(Administrate::MCP::ApiKey.count).to eq(0)
    end

    it 'grants write access when the host overrides the refusal' do
      create_key(write_access: '1', path: '/console/writable_administrate_mcp_api_keys')

      expect(Administrate::MCP::ApiKey.last).to be_write_access
    end
  end

  describe 'revoking a key' do
    let!(:key) { create(:administrate_mcp_api_key, admin:) }

    it 'revokes rather than deletes, so the row still explains what the token was' do
      expect { delete "/console/administrate_mcp_api_keys/#{key.id}", headers: }
        .to change { key.reload.revoked_at }.from(nil)

      expect(response).to redirect_to('/console/administrate_mcp_api_keys')
      expect(Administrate::MCP::ApiKey.count).to eq(1)
    end
  end

  describe 'listing' do
    it "resolves the engine's model and dashboard, which the controller name does not spell" do
      create(:administrate_mcp_api_key, admin:, name: 'listed key')

      get '/console/administrate_mcp_api_keys', headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('listed key')
    end

    it 'lists feedback newest first' do
      create(:administrate_mcp_feedback, admin:, resource_name: 'older_report', created_at: 2.days.ago)
      create(:administrate_mcp_feedback, admin:, resource_name: 'newer_report', created_at: 1.hour.ago)

      get '/console/administrate_mcp_feedbacks', headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.body.index('newer_report')).to be < response.body.index('older_report')
    end
  end
end
