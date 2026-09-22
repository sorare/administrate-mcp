# frozen_string_literal: true

module Administrate
  module MCP
    # Administrate console for the API keys admins authenticate to the MCP server with. The host
    # keeps its own base controller, authentication and policies; this supplies the resource wiring
    # and the two actions a write-once credential needs, because the plaintext key exists only in
    # the response that creates it.
    #
    # A host that lets some admins mint write-enabled keys overrides `mcp_write_access_allowed?`.
    module ApiKeysAdmin
      extend ActiveSupport::Concern
      include ResourceController

      TOKEN_PREFIX_LENGTH = 13
      WRITE_ACCESS_REFUSAL = 'Only administrators allowed to grant write access can create write-enabled API keys.'

      included do
        administrate_mcp_resource Administrate::MCP::ApiKey, dashboard: AdministrateMcpApiKeyDashboard
      end

      def create
        token = Administrate::MCP::ApiKey.generate_token
        api_key = build_mcp_api_key(token)
        authorize_mcp_resource(api_key)

        if api_key.write_access? && !mcp_write_access_allowed?
          return render_mcp_form_error(api_key, WRITE_ACCESS_REFUSAL)
        end

        if api_key.save
          redirect_to_mcp_index("MCP API key created. Copy it now, it is not shown again: #{token}")
        else
          render_mcp_form_error(api_key, api_key.errors.full_messages.join(', '))
        end
      end

      def destroy
        api_key = requested_resource
        authorize_mcp_resource(api_key)
        api_key.revoke!

        redirect_to_mcp_index("API key '#{api_key.name}' has been revoked.")
      end

      private

      def build_mcp_api_key(token)
        Administrate::MCP::ApiKey.new(
          admin: mcp_api_key_owner,
          token_digest: Administrate::MCP::ApiKey.digest_token(token),
          token_prefix: token[0, TOKEN_PREFIX_LENGTH],
          name: mcp_api_key_name,
          write_access: mcp_write_access_requested?
        )
      end

      def mcp_api_key_owner
        Administrate::MCP.config.current_admin.call(self)
      end

      def mcp_api_key_name
        params.dig(resource_name, :name).presence || 'Unnamed key'
      end

      def mcp_write_access_requested?
        ActiveModel::Type::Boolean.new.cast(params.dig(resource_name, :write_access)) || false
      end

      # A write-enabled key carries every write tool, so granting one is a decision the host makes.
      def mcp_write_access_allowed?
        false
      end

      def authorize_mcp_resource(api_key)
        authorize(api_key) if respond_to?(:authorize, true)
      end

      def redirect_to_mcp_index(notice)
        redirect_to({ action: :index }, notice:, status: :see_other)
      end

      def render_mcp_form_error(api_key, message)
        flash.now[:error] = message
        render :new, locals: { page: Administrate::Page::Form.new(dashboard, api_key) }, status: :unprocessable_content
      end

      def scoped_resource
        super.order(created_at: :desc)
      end
    end
  end
end
