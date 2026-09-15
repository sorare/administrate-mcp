# administrate-mcp

A Rails engine that exposes your [Administrate](https://github.com/thoughtbot/administrate)
dashboards over the [Model Context Protocol](https://modelcontextprotocol.io), so an MCP client
(Claude Code, Claude Desktop, any other) can read and act on your admin data with the same
permissions the admin UI enforces.

You get:

- three generic tools built from your dashboards — `admin_resource_list_resources`,
  `admin_resource_list`, `admin_resource_show`
- a feedback tool, `report_mcp_improvement`, so users can tell you what the server got wrong
- two optional Sidekiq tools
- write actions you declare on a dashboard with `mcp_action`, each published as its own tool
- API key and OAuth 2.1 (PKCE + Dynamic Client Registration) authentication

Nothing in the engine knows about your application. Everything host-specific goes through
`Administrate::MCP.configure`.

## Installation

```ruby
# Gemfile
gem 'administrate-mcp'
```

Copy the migrations and run them:

```sh
bin/rails administrate_mcp:install:migrations
bin/rails db:migrate
```

The tables are `administrate_mcp_api_keys`, `administrate_mcp_feedbacks`,
`administrate_mcp_oauth_applications`, `administrate_mcp_oauth_access_grants` and
`administrate_mcp_oauth_access_tokens`. They use uuid primary keys and a uuid `admin_id` column
that is indexed but carries no foreign key constraint, so the engine works with any admin table.

## Configuration

Configure in an initializer — `config/initializers/administrate_mcp.rb`. It must run before the
engine's models load, because the `admin` association reads `admin_class_name`.

```ruby
Administrate::MCP.configure do |c|
  c.server_name = 'acme_admin'
  c.server_version = '1.0.0'

  c.admin_class_name = 'Administrator'
  c.current_admin = ->(controller) { controller.send(:warden)&.authenticate(scope: :administrator) }
  c.sign_in = lambda do |controller|
    controller.send(:store_location_for, :administrator, controller.request.fullpath)
    controller.redirect_to(controller.main_app.new_administrator_session_path)
  end

  c.issuer = ->(request) { request.subdomain == 'admin-mcp' ? request.base_url : 'https://admin-mcp.acme.com' }
  c.admin_origin = ->(request) { request.subdomain == 'admin' ? request.base_url : 'https://admin.acme.com' }
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
  c.on_feedback = ->(feedback) { SlackNotifier.notify(notification_type: :mcp_feedback, blocks: blocks_for(feedback)) }
end
```

### The full configuration object

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
                :sign_in,
                :admin_class_name,
                :authorization,
                :default_required_roles,
                :tool_paths,
                :dashboard_paths,
                :instrument,
                :on_tool_call,
                :on_feedback,
                :allow_localhost_redirects,
                :api_key_token_prefix,
                :default_client_name,
                :sidekiq_stats_provider,
                :admin_route_namespace,
                :admin_url_options,
                :skipped_field_classes,
                :has_many_field_classes,
                :field_serializers

  def assign_identity
    @server_name = 'administrate_mcp'
    @server_version = VERSION
    @issuer = nil
    @admin_origin = nil
    @current_admin = ->(_controller) {}
    @sign_in = nil
    @admin_class_name = 'Administrator'
    @authorization = default_authorization
    @default_required_roles = []
    @tool_paths = []
    @dashboard_paths = nil
  end

  def assign_hooks
    @instrument = ->(tool_name:, admin:, &block) { block.call }
    @on_tool_call = ->(tool_name:, admin:, arguments:, scopes:) {}
    @on_feedback = ->(feedback) {}
    @allow_localhost_redirects = true
    @api_key_token_prefix = 'amcp_'
    @default_client_name = 'MCP Client'
    @sidekiq_stats_provider = nil
  end

  def assign_fields
    @admin_route_namespace = :admin
    @admin_url_options = {}
    @skipped_field_classes = SKIPPED_FIELD_CLASSES.dup
    @has_many_field_classes = HAS_MANY_FIELD_CLASSES.dup
    @field_serializers = FIELD_SERIALIZERS.dup
  end

  def register_field(class_name, as: nil, &serializer); end
  def skip_field(*class_names); end
  def register_has_many_field(*class_names); end

  def admin_class; end
  def issuer_for(request = nil); end
  def admin_origin_for(request = nil); end
  def dashboard_directories; end
end
```

| Entry | Default | What it does |
| --- | --- | --- |
| `server_name` | `'administrate_mcp'` | Name reported in the MCP handshake |
| `server_version` | the gem version | Version reported in the handshake |
| `issuer` | `nil` | MCP origin. String or a proc taking the request |
| `admin_origin` | `nil` | Admin origin, where the consent screen lives. String or proc |
| `current_admin` | returns `nil` | Proc taking the OAuth controller, returning the signed-in admin |
| `sign_in` | `nil` (renders 401) | Proc taking the OAuth controller, sending an anonymous visitor to sign in |
| `admin_class_name` | `'Administrator'` | Class the `admin_id` column points at |
| `authorization` | Pundit if defined, else Permissive | Adapter: `authorize!`, `authorized?`, `authorize_roles!` |
| `default_required_roles` | `[]` | Roles a tool requires unless it declares its own |
| `tool_paths` | `[]` | Directories scanned for extra `BaseTool` subclasses |
| `dashboard_paths` | `app/dashboards` | Where dashboards are found |
| `instrument` | yields | Around-hook `(tool_name:, admin:, &block)` |
| `on_tool_call` | no-op | Audit hook `(tool_name:, admin:, arguments:, scopes:)`, after the permission checks |
| `on_feedback` | no-op | Called with each new `Feedback` record |
| `allow_localhost_redirects` | `true` | Whether loopback OAuth redirect URIs are accepted |
| `api_key_token_prefix` | `'amcp_'` | Prefix that marks a bearer token as an API key |
| `default_client_name` | `'MCP Client'` | Name given to a dynamically registered client that sends no `client_name` |
| `sidekiq_stats_provider` | `nil` | Object answering `counts`, `total_counts`, `queues`, `stats_cleared_at`; a class name String or a Proc is resolved lazily so autoloaded providers can be named in an initializer |
| `admin_route_namespace` | `:admin` | Namespace used to build record URLs |
| `admin_url_options` | `{}` | Options passed to `polymorphic_url`; when no `:host` is given, host, protocol and port are taken from `admin_origin` |
| `skipped_field_classes` | Password | Field class names never serialized |
| `has_many_field_classes` | HasMany | Field class names treated as expandable collections |
| `field_serializers` | see above | Field class name to serializer |

### Authorization adapters

`Authorization::Permissive` grants every action to every authenticated admin. `Authorization::Pundit`
runs the policy for the resource exactly as the Administrate UI does — `index?` to list, `show?` to
read, and the action's own predicate for a write action.

Both inherit `authorize_roles!` from `Authorization::Base`: when the admin answers `can_access?`, a
tool's `requires_roles` is checked against it; an admin that does not answer `can_access?` is never
refused on role grounds.

Write your own by answering three methods:

```ruby
class MyAuthorization < Administrate::MCP::Authorization::Base
  def authorize!(admin, record_or_class, action); end     # raise Administrate::MCP::UnauthorizedError
  def authorized?(admin, record_or_class, action); end    # true / false
  def authorize_roles!(admin, roles); end                 # optional, inherited
end
```

### Serializing your own field classes

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

## Routes

The consent screen must be served on the admin origin, where the admin's session lives, while the
JSON-RPC and metadata endpoints live on a dedicated MCP origin. Draw each set inside your own
constraints:

```ruby
Rails.application.routes.draw do
  constraints ->(request) { request.subdomain == 'admin-mcp' } do
    Administrate::MCP::Routes.draw_mcp_origin(self)
  end

  constraints subdomain: 'admin' do
    Administrate::MCP::Routes.draw_admin_origin(self)
  end
end
```

`draw_mcp_origin` adds `/.well-known/oauth-protected-resource`,
`/.well-known/oauth-authorization-server`, `POST /oauth/register`, `POST /oauth/token` and the
JSON-RPC endpoint at `/`. `draw_admin_origin` adds `GET` and `POST /mcp/oauth/authorize`; pass
`path:` to move it.

To serve everything on one origin instead, mount the engine:

```ruby
mount Administrate::MCP::Engine => '/mcp'
```

## Dashboard declarations

```ruby
class OrderDashboard < Administrate::BaseDashboard
  MCP_DESCRIPTION = 'Customer orders, including the cancelled ones the UI hides by default.'
  MCP_BASE_SCOPE = -> { Order.unscope(where: :state) }

  COLLECTION_FILTERS = {
    unpaid: ->(scope) { scope.where(paid_at: nil) },
    for_country: ->(scope, code) { scope.where(country: code) }
  }.freeze

  mcp_action :refund,
             description: 'Refund an order.',
             params: { reason: { type: 'string', description: 'Why the order is being refunded.' } } do |record:, admin:, params:|
    Orders::Refund.call!(order: record, admin:, reason: params[:reason])
  end
end
```

- `MCP_DESCRIPTION` tells the client what the resource is.
- `MCP_SKIPPED_ATTRIBUTES = %i[email]` keeps attributes visible in the admin UI but out of MCP
  reads, listings and field selection.
- `MCP_EXPOSED = false` leaves the dashboard out of the MCP registry entirely.
- Namespaced models work through the dashboard's own `self.model`, as in Administrate.
- `MCP_BASE_SCOPE` replaces the model's default scope for MCP reads, mirroring an admin controller's
  `scoped_resource`.
- `COLLECTION_FILTERS` are published as filters; a one-argument lambda is a boolean filter, a
  two-argument one takes a value. Foreign key columns are filterable without being declared.
- `mcp_action` publishes one tool per declaration. It requires the OAuth `write` scope *and* the
  authorization predicate (`refund?` by default, or `predicate:`) on the loaded record. The block
  receives `record:`, `admin:` and `params:`; a result answering `success? == false` is reported as
  an error.

## Authentication

**API keys.** Create one yourself and hand the plaintext to the user once:

```ruby
token = Administrate::MCP::ApiKey.generate_token
Administrate::MCP::ApiKey.create!(admin:, name: 'Laptop', token_digest: Administrate::MCP::ApiKey.digest_token(token),
                                  token_prefix: token[0, 13])
```

Only the digest is stored. Keys are read-only unless `write_access` is set.

**OAuth 2.1.** Clients register themselves, send the user to the consent screen on the admin origin,
and exchange the code with PKCE. Access tokens last a week, authorization codes ten minutes, and
refreshing revokes the old token.

The JSON-RPC endpoint authenticates by bearer token only and never reads the session cookie: hosts
routinely share a session across sibling subdomains, and a browser signed into the admin UI must not
thereby be able to drive the protocol endpoint.

## Rate limiting

The gem does not depend on rack-attack. If you use it, these are the throttles to add — or call
`Administrate::MCP::RackAttack.throttles(host: 'admin-mcp')` from your own initializer, which
registers exactly these:

| Name | Request | Limit |
| --- | --- | --- |
| `mcp_oauth/register/ip` | `POST /oauth/register` on the MCP host | 5 per minute per IP |
| `mcp_oauth/register/ip-day` | `POST /oauth/register` on the MCP host | 50 per day per IP |
| `mcp_oauth/token/ip` | `POST /oauth/token` on the MCP host | 10 per minute per IP |
| `mcp_oauth/authorize/ip` | `GET /mcp/oauth/authorize` | 20 per minute per IP |

## Customising the consent screen

Override `app/views/administrate/mcp/o_auth/authorize.html.erb` in your application. The template
has `@application`, `@redirect_uri`, `@redirect_host` and `@scopes`.

## Feedback housekeeping

`Administrate::MCP::CleanOldFeedbacks.call(till: 2.months.ago)` deletes one batch of 10,000 and
reports `more?`; schedule it however your app schedules work.

## Design decisions

- **Everything host-specific is configuration, not a subclass.** The engine references no constant
  it does not own, at load time or at run time. That is why field serializers are keyed on class
  *names*, why the Sidekiq stats tool needs a provider object, and why auditing and instrumentation
  are procs.
- **`admin`, not `administrator`.** The owner association, the `server_context` key and the
  `execute(admin:)` keyword all use `admin`. Applications that called the Sorare originals with
  `administrator:` need to rename that one keyword in their own tools and `mcp_action` blocks.
- **No foreign key on `admin_id`.** Hosts disagree about which table admins live in, and some forbid
  cross-table constraints. The column is indexed; referential integrity is the host's call.
- **Roles live on the authorization adapter.** Roles are an authorization concern, and hosts that
  have none get the behaviour for free: an admin that does not answer `can_access?` is never refused
  on role grounds. `default_required_roles` supplies the gate for tools that declare none;
  `report_mcp_improvement` opts out, because reporting a bad description is not privileged.
- **Files named `o_auth_*.rb`, classes named `OAuth*`.** Zeitwerk derives the constant from the file
  name, and `oauth_access_token.rb` would produce `OauthAccessToken` unless the host registered an
  `OAuth` acronym globally. Naming the file `o_auth_access_token.rb` gets the right constant with no
  inflection at all. The only inflection the engine registers is `mcp` → `MCP`, and it registers it
  on the autoloader rather than in `ActiveSupport::Inflector`, so your application's `camelize` is
  untouched.
- **Routes are Rack lambdas, not `"controller#action"` strings.** Rails resolves those strings
  through the global inflections, which would have reintroduced the acronym requirement.
- **Tool names are unchanged** — `admin_resource_list`, `admin_resource_show`,
  `admin_resource_list_resources`, `report_mcp_improvement`, `sidekiq_stats`, `sidekiq_retries` — so
  existing clients keep working.
- **`FastSearch` ships with the engine.** The list tool searches exactly by default, with `*` as the
  only wildcard, so searching an id or a slug does not match every row that contains it.
- **Feedback services are plain objects.** `ReportImprovement` and `CleanOldFeedbacks` return a
  result struct and do no scheduling; the host decides how and when to run them.

## Development

```sh
bundle install
createdb administrate_mcp_test
bundle exec rspec
bundle exec rubocop
```

The dummy application under `spec/dummy` has an `Admin`, a `Widget` (with `MCP_BASE_SCOPE` and
collection filters) and a `Gadget` (with a `belongs_to` and an `mcp_action`). Point the specs at
another Postgres with `ADMINISTRATE_MCP_DB_HOST`, `_PORT`, `_USER`, `_PASSWORD` and `_NAME`.

## Licence

MIT. Copyright Sorare.
