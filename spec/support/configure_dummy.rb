# frozen_string_literal: true

# The configuration the dummy application ships with. Re-applied after every example so a spec
# that overrides one entry cannot leak into the next.
module ConfigureDummy
  def self.apply!
    Administrate::MCP.configure do |c|
      c.server_name = 'dummy_admin'
      c.server_version = '1.2.3'
      c.admin_class_name = 'Admin'
      c.api_key_token_prefix = 'amcp_'
      c.issuer = ->(request) { request&.subdomain == 'admin-mcp' ? request.base_url : 'https://admin-mcp.example.com' }
      c.admin_origin = ->(request) { request&.subdomain == 'admin' ? request.base_url : 'https://admin.example.com' }
      c.current_admin = ->(controller) { CurrentAdmin.for(controller) }
      c.sign_in = ->(controller) { controller.redirect_to('http://admin.example.com/admins/sign_in') }
      c.admin_url_options = { host: 'admin.example.com', protocol: 'https' }
      c.authorization = Administrate::MCP::Authorization::Permissive.new
    end
  end
end

# Stands in for the host's session lookup: specs set the admin id in the request headers.
module CurrentAdmin
  def self.for(controller)
    id = controller.request.headers['X-Dummy-Admin']
    id && Admin.find_by(id:)
  end
end
