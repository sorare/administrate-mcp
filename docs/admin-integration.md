# Admin integration

[Back to README](../README.md)

## Exposing the engine's own tables in your admin

The engine's records keep their namespace in `model_name`, so `Administrate::MCP::ApiKey` routes as
`administrate_mcp_api_keys` and never shadows a resource of your own called `api_keys`. Administrate
needs three things to manage a namespaced model:

```ruby
# config/routes.rb, inside your admin namespace
namespace :admin do
  resources :administrate_mcp_api_keys
  # Only needed when config.persist_feedback is true; the table itself only exists then too.
  resources :administrate_mcp_feedbacks, only: %i[index show destroy]
end

# app/dashboards/administrate_mcp/api_key_dashboard.rb
module AdministrateMcp
  class ApiKeyDashboard < Administrate::BaseDashboard
    ATTRIBUTE_TYPES = { id: Field::String, name: Field::String, admin: Field::BelongsTo }.freeze
    COLLECTION_ATTRIBUTES = %i[id name].freeze
    SHOW_PAGE_ATTRIBUTES = %i[id name admin].freeze
    FORM_ATTRIBUTES = %i[name].freeze

    def self.model
      Administrate::MCP::ApiKey
    end
  end
end

# app/controllers/admin/administrate_mcp_api_keys_controller.rb
module Admin
  class AdministrateMcpApiKeysController < Admin::ApplicationController
    def resource_class = Administrate::MCP::ApiKey
    def dashboard_class = AdministrateMcp::ApiKeyDashboard
  end
end
```

The MCP registry finds the dashboard through `self.model`, registers it as
`administrate/mcp/api_key`, and builds record URLs from the namespaced route key.

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
