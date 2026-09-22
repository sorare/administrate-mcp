# Admin integration

[Back to README](../README.md)

## The API key and feedback consoles

The engine ships the console for its own tables: two Administrate dashboards and two controller
concerns. Include them in controllers of your own, so that authentication, the base controller and
the policies stay yours:

```ruby
# config/routes.rb, inside your admin namespace
namespace :admin do
  resources :administrate_mcp_api_keys, only: %i[index show new create destroy]
  # Only when config.persist_feedback is true; the table exists only then.
  resources :administrate_mcp_feedbacks, only: %i[index show edit update]
end

# app/dashboards/administrate_mcp_api_key_dashboard.rb
class AdministrateMcpApiKeyDashboard < Administrate::MCP::ApiKeyDashboard
end

# app/dashboards/administrate_mcp_feedback_dashboard.rb
class AdministrateMcpFeedbackDashboard < Administrate::MCP::FeedbackDashboard
end

# app/controllers/admin/administrate_mcp_api_keys_controller.rb
module Admin
  class AdministrateMcpApiKeysController < Admin::ApplicationController
    include Administrate::MCP::ApiKeysAdmin
  end
end

# app/controllers/admin/administrate_mcp_feedbacks_controller.rb
module Admin
  class AdministrateMcpFeedbacksController < Admin::ApplicationController
    include Administrate::MCP::FeedbacksAdmin
  end
end
```

`ApiKeysAdmin` generates the key, stores its digest, and puts the plaintext in the flash of the
redirect that created it, because that response is the only place it can ever be read. `destroy`
revokes rather than deletes, so the row still says what the token was. Both concerns point
Administrate at the engine's model, which the controller's own name cannot spell.

The two empty subclasses are the part the engine cannot write for you. Administrate finds a
dashboard by camelizing the controller's name, and an application that registers MCP as an
inflection acronym expects `AdministrateMCPApiKeyDashboard` where one that does not expects
`AdministrateMcpApiKeyDashboard`. Name the file `administrate_mcp_api_key_dashboard.rb` and the
class whatever your own inflections produce for it; the columns come from the engine's class.

The key owner comes from `config.current_admin`, so no host code decides it twice. If your base
controller offers Pundit's `authorize`, both actions call it.

### What a host overrides

| Method | Default | Override to |
| --- | --- | --- |
| `mcp_write_access_allowed?` | `false` | let some admins mint write-enabled keys |
| `mcp_api_key_owner` | `config.current_admin` | attribute the key to someone else |
| `scoped_resource` | every key, newest first | show an admin only their own keys |

```ruby
module Admin
  class AdministrateMcpApiKeysController < Admin::ApplicationController
    include Administrate::MCP::ApiKeysAdmin

    private

    def mcp_write_access_allowed?
      policy(Administrate::MCP::ApiKey).grant_write_access?
    end

    def scoped_resource
      current_administrator.full_access? ? super : super.where(admin: current_administrator)
    end
  end
end
```

### Different columns

Redefine the constants you want to change in your subclass:

```ruby
class AdministrateMcpApiKeyDashboard < Administrate::MCP::ApiKeyDashboard
  COLLECTION_ATTRIBUTES = %i[name last_used_at].freeze
end
```

For a console mounted at a path Administrate cannot derive the dashboard from, name it explicitly:

```ruby
module Admin
  class AdministrateMcpApiKeysController < Admin::ApplicationController
    include Administrate::MCP::ApiKeysAdmin
    administrate_mcp_resource Administrate::MCP::ApiKey, dashboard: ApiKeyConsoleDashboard
  end
end
```

## Listing the engine's tables over the protocol

The consoles above are not MCP resources. The registry only reads your own dashboard directory, so
the engine's dashboards are invisible to it whatever they are called. To expose a key list over the
protocol, declare a dashboard in `app/dashboards` with an `MCP_DESCRIPTION` and a `self.model`:

```ruby
# app/dashboards/administrate_mcp/api_key_dashboard.rb
module AdministrateMcp
  class ApiKeyDashboard < Administrate::BaseDashboard
    MCP_DESCRIPTION = 'API keys admins authenticate to the MCP server with.'

    ATTRIBUTE_TYPES = { id: Field::String, name: Field::String, admin: Field::BelongsTo }.freeze
    COLLECTION_ATTRIBUTES = %i[id name].freeze
    SHOW_PAGE_ATTRIBUTES = %i[id name admin].freeze
    FORM_ATTRIBUTES = %i[name].freeze

    def self.model
      Administrate::MCP::ApiKey
    end
  end
end
```

The registry finds it through `self.model`, registers it as `administrate/mcp/api_key`, and builds
record URLs from the namespaced route key, so it never shadows a resource of your own called
`api_keys`.

## Customising the consent screen

Override `app/views/administrate/mcp/o_auth/authorize.html.erb` in your application. The template
has `@application`, `@redirect_uri`, `@redirect_host` and `@scopes`.

## Feedback housekeeping

The `administrate_mcp_feedbacks` table, its dashboard and this housekeeping service are only needed
when `config.persist_feedback` is `true`. With it off, `report_mcp_improvement` still works and
`on_feedback` still fires, just without a row behind it, and the table can be left out entirely; see
[docs/configuration.md](configuration.md) for the setting.

`Administrate::MCP::CleanOldFeedbacks.call(till: 2.months.ago)` deletes one batch of 10,000 and
reports `more?`; schedule it however your app schedules work.

`ReportImprovement`, which backs the `report_mcp_improvement` tool, is a plain object in the same
style: it returns a result struct and does no scheduling of its own. Both services leave the decision
of how and when to run them to the host application.
