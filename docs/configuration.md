# Configuration

[Back to README](../README.md)

Configure the engine in an initializer, `config/initializers/administrate_mcp.rb`. It must run
before the engine's models load, because the `admin` association reads `admin_class_name` and
`admin_foreign_key`.

```ruby
Administrate::MCP.configure do |c|
  c.server_name = 'acme_admin'
  c.server_version = '1.0.0'

  c.admin_class_name = 'Administrator'
  c.admin_foreign_key = :administrator_id
  c.current_admin = ->(controller) { controller.send(:warden)&.authenticate(scope: :administrator) }
  c.admin_active = ->(admin) { admin.admin? && admin.anonymized_at.nil? }
  c.sign_in = lambda do |controller|
    controller.send(:store_location_for, :administrator, controller.request.fullpath)
    controller.redirect_to(controller.main_app.new_administrator_session_path)
  end

  # These procs are also called without a request, when the engine builds a record URL outside a
  # request cycle, so guard the dereference.
  c.issuer = ->(request) { request&.subdomain == 'admin-mcp' ? request.base_url : 'https://admin-mcp.acme.com' }
  c.admin_origin = ->(request) { request&.subdomain == 'admin' ? request.base_url : 'https://admin.acme.com' }
  c.admin_url_options = { subdomain: 'admin' }

  c.authorization = Administrate::MCP::Authorization::Pundit.new
  c.default_required_roles = [:full_access]

  c.tool_paths = [Rails.root.join('app/mcp_tools')]

  c.instrument = lambda do |tool_name:, admin:, &block|
    Datadog::Tracing.trace('call', resource: tool_name, service: 'mcp_tool') { block.call }
  end
  c.on_tool_call = lambda do |tool_name:, admin:, arguments:, scopes:|
    Admin::AuditOperation.call!(administrator_id: admin.id, request_method: 'POST',
                                request_url: "mcp://tools/#{tool_name}", params: arguments)
  end
  c.persist_feedback = true
  c.on_feedback = ->(report) { SlackNotifier.notify(notification_type: :mcp_feedback, blocks: blocks_for(report)) }
end
```

Set `admin_foreign_key` when the host's own admin table already has a foreign key column under a
different name, for example a live credentials table called `administrator_id`, and renaming that
column is not something you want to do. The association is still called `admin` everywhere the
engine's API uses it; only the column it reads and writes changes.

`report_mcp_improvement` gives users of the MCP server a way to flag what the server got wrong; the
gem's job stops at reporting that signal to `on_feedback`. Storing what it reports, showing it in a
dashboard and cleaning up old rows is an opinion about how a host wants to handle the signal, not
something every host needs, so it is batteries-included rather than mandatory: set
`persist_feedback` to `true` to have the gem create an `Administrate::MCP::Feedback` row before
calling `on_feedback`, expose it in your admin as described in
[docs/admin-integration.md](admin-integration.md), and clean old rows up with
`Administrate::MCP::CleanOldFeedbacks`. Leave it `false`, the default, and `on_feedback` still fires
with the same report, just without a persisted record behind it, and the `administrate_mcp_feedbacks`
table is never touched. Set `feedback_tool` to `false` to stop publishing `report_mcp_improvement`
at all.

## The full configuration object

```ruby
class Configuration
  SKIPPED_FIELD_CLASSES = ['Administrate::Field::Password'].freeze

  HAS_MANY_FIELD_CLASSES = ['Administrate::Field::HasMany'].freeze

  FIELD_SERIALIZERS = {
    'Administrate::Field::HasMany' => :has_many,
    'Administrate::Field::Polymorphic' => :polymorphic,
    'Administrate::Field::BelongsTo' => :belongs_to,
    'Administrate::Field::HasOne' => :belongs_to,
    'Administrate::Field::DateTime' => :datetime,
    'Administrate::Field::Date' => :datetime,
    'Administrate::Field::Time' => :datetime,
    'Administrate::Field::Enum' => :enum,
    'Administrate::Field::Select' => :enum,
    'Administrate::Field::Shrine' => :attachment,
    'Administrate::Field::String' => :scalar,
    'Administrate::Field::Text' => :scalar,
    'Administrate::Field::Email' => :scalar,
    'Administrate::Field::Url' => :scalar,
    'Administrate::Field::Number' => :scalar,
    'Administrate::Field::Boolean' => :scalar
  }.freeze

  attr_accessor :server_name,
                :server_version,
                :issuer,
                :admin_origin,
                :current_admin,
                :admin_active,
                :identity_fallback,
                :oauth,
                :sign_in,
                :admin_class_name,
                :admin_foreign_key,
                :authorization,
                :default_required_roles,
                :tool_paths,
                :dashboard_paths,
                :instrument,
                :on_tool_call,
                :on_feedback,
                :on_error,
                :allow_localhost_redirects,
                :default_client_name,
                :persist_feedback,
                :feedback_tool,
                :sidekiq_stats_provider,
                :admin_route_namespace,
                :admin_url_options,
                :skipped_field_classes,
                :has_many_field_classes,
                :field_serializers

  attr_reader :api_key_token_prefix

  def assign_identity
    @server_name = 'administrate_mcp'
    @server_version = VERSION
    @issuer = nil
    @admin_origin = nil
    @current_admin = ->(_controller) {}
    @admin_active = ->(_admin) { true }
    @identity_fallback = ->(_request) {}
    @oauth = true
    @sign_in = nil
    @admin_class_name = 'Administrator'
    @admin_foreign_key = :admin_id
    @authorization = default_authorization
    @default_required_roles = []
    @tool_paths = []
    @dashboard_paths = nil
  end

  def assign_hooks
    @instrument = ->(tool_name:, admin:, &block) { block.call }
    @on_tool_call = ->(tool_name:, admin:, arguments:, scopes:) {}
    @on_feedback = ->(report) {}
    @on_error = ->(exception) {}
    @allow_localhost_redirects = true
    @api_key_token_prefix = 'amcp_'
    @default_client_name = 'MCP Client'
    @persist_feedback = false
    @feedback_tool = true
    @sidekiq_stats_provider = nil
  end

  def assign_fields
    @admin_route_namespace = :admin
    @admin_url_options = {}
    @skipped_field_classes = SKIPPED_FIELD_CLASSES.dup
    @has_many_field_classes = HAS_MANY_FIELD_CLASSES.dup
    @field_serializers = FIELD_SERIALIZERS.dup
  end

  def api_key_token_prefix=(prefix); end          # raises ArgumentError on a blank prefix

  def register_field(class_name, as: nil, &serializer); end
  def skip_field(*class_names); end
  def register_has_many_field(*class_names); end

  def issuer_for(request = nil); end
  def admin_origin_for(request = nil); end
  def dashboard_directories; end
end
```

| Entry                       | Default                            | What it does                                                                                                                                                                     |
| --------------------------- | ---------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `server_name`               | `'administrate_mcp'`               | Name reported in the MCP handshake                                                                                                                                               |
| `server_version`            | the gem version                    | Version reported in the handshake                                                                                                                                                |
| `issuer`                    | `nil`                              | MCP origin. String or a proc taking the request                                                                                                                                  |
| `admin_origin`              | `nil`                              | Admin origin, where the consent screen lives. String or proc                                                                                                                     |
| `current_admin`             | returns `nil`                      | Proc taking the OAuth controller, returning the signed-in admin                                                                                                                  |
| `admin_active`              | `true`                             | Proc taking the authenticated admin. Return false and the call is refused with 401 `inactive_admin`, so a credential does not outlive the person's admin status                  |
| `identity_fallback`         | returns `nil`                      | Proc taking the request, returning an `Authentication::Identity` or nil, consulted when no credential the engine issued matched                                                  |
| `oauth`                     | `true`                             | Whether the engine serves its own OAuth 2.1 server. False draws no OAuth routes and never looks an access token up                                                               |
| `sign_in`                   | `nil` (renders 401)                | Proc taking the OAuth controller, sending an anonymous visitor to sign in                                                                                                        |
| `admin_class_name`          | `'Administrator'`                  | Class the admin foreign key column points at                                                                                                                                     |
| `admin_foreign_key`         | `:admin_id`                        | Column on the engine's own tables that stores the owning admin's id. The association is still called `admin`; only the column name changes                                       |
| `authorization`             | Pundit if defined, else Permissive | Adapter: `authorize!`, `authorized?`, `authorize_roles!`                                                                                                                         |
| `default_required_roles`    | `[]`                               | Roles a tool requires unless it declares its own                                                                                                                                 |
| `tool_paths`                | `[]`                               | Directories scanned for extra `BaseTool` subclasses                                                                                                                              |
| `dashboard_paths`           | `app/dashboards`                   | Where dashboards are found                                                                                                                                                       |
| `instrument`                | yields                             | Around hook `(tool_name:, admin:, &block)`                                                                                                                                       |
| `on_tool_call`              | no-op                              | Audit hook `(tool_name:, admin:, arguments:, scopes:)`, after the permission checks                                                                                              |
| `on_feedback`               | no-op                              | Called with each `FeedbackReport`, whether or not it was persisted                                                                                                               |
| `on_error`                  | no-op                              | Called with an exception the engine swallowed, so you can report it                                                                                                              |
| `allow_localhost_redirects` | `true`                             | Whether loopback OAuth redirect URIs are accepted. Inert when `oauth` is false                                                                                                   |
| `api_key_token_prefix`      | `'amcp_'`                          | Prefix that marks a bearer token as an API key. Cannot be blank                                                                                                                  |
| `default_client_name`       | `'MCP Client'`                     | Name given to a dynamically registered client that sends no `client_name`. Inert when `oauth` is false                                                                           |
| `persist_feedback`          | `false`                            | Whether `report_mcp_improvement` creates an `Administrate::MCP::Feedback` row before calling `on_feedback`. False needs no `administrate_mcp_feedbacks` table at all             |
| `feedback_tool`             | `true`                             | Whether `report_mcp_improvement` is published                                                                                                                                    |
| `sidekiq_stats_provider`    | `nil`                              | Object answering `counts`, `total_counts`, `queues`, `stats_cleared_at`; a class name String or a Proc is resolved lazily so autoloaded providers can be named in an initializer |
| `admin_route_namespace`     | `:admin`                           | Namespace record URLs are built from                                                                                                                                             |
| `admin_url_options`         | `{}`                               | Options passed to `polymorphic_url`; when no `:host` is given, host, protocol and port are taken from `admin_origin`                                                             |
| `skipped_field_classes`     | Password                           | Field class names never serialized                                                                                                                                               |
| `has_many_field_classes`    | HasMany                            | Field class names treated as expandable collections                                                                                                                              |
| `field_serializers`         | see above                          | Field class name to serializer                                                                                                                                                   |

## Authorization adapters

`Authorization::Permissive` grants every action to every authenticated admin. `Authorization::Pundit`
runs the policy for the resource exactly as the Administrate UI does: `index?` to list, `show?` to
read, and the action's own predicate for a write action.

Both inherit `authorize_roles!` from `Authorization::Base`: a tool's `requires_roles` (or
`default_required_roles`) is checked with `admin.can_access?(*roles)`. An admin class that does not
answer `can_access?` raises `Administrate::MCP::ConfigurationError` rather than letting the call
through. Clear `default_required_roles`, give the class the method, or override `authorize_roles!`.

`report_mcp_improvement` requires no role: reporting that a tool description or result is wrong is
not a privileged action, so it stays open to any authenticated admin regardless of
`default_required_roles`.

Write your own by answering three methods:

```ruby
class MyAuthorization < Administrate::MCP::Authorization::Base
  def authorize!(admin, record_or_class, action); end     # raise Administrate::MCP::UnauthorizedError
  def authorized?(admin, record_or_class, action); end    # true / false
  def authorize_roles!(admin, roles); end                 # optional, inherited
end
```

## Serializing your own field classes

The engine matches field classes by name, walking the field's ancestors, so it never references a
class you own:

```ruby
Administrate::MCP.configure do |c|
  c.register_field('MonetaryAmountsField') { |source| source.value&.serialize }
  c.register_field('AnyAttachmentField', as: :attachment)
  c.register_has_many_field('HasManyNonAssociationField')
  c.skip_field('GridField', 'HasOneNonAssociationField')
end
```

A field class that answers `mcp_value(record, attr_name)` and is not registered is asked for its own
value. An unregistered field class with no `mcp_value` falls back to its raw value.

`Field::Text` and `Field::Url`, along with every other field class registered as `:scalar`,
serialize a nil value as `null` rather than an empty string.
