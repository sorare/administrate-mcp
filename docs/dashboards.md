# Dashboard declarations

[Back to README](../README.md)

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

  mcp_action :import,
             on: :collection,
             description: 'Import an order from a marketplace.',
             params: { reference: 'The marketplace order reference.' } do |admin:, params:|
    Orders::Import.call!(reference: params[:reference], admin:)
  end
end
```

Every `MCP_` constant and `COLLECTION_FILTERS` is read off the dashboard itself, never inherited, so
a constant of the same name defined at the top level of your application, or on a shared dashboard
base class, is not applied to every resource. A subclass that wants one declares it.

- `MCP_DESCRIPTION` tells the client what the resource is.
- `MCP_SKIPPED_ATTRIBUTES = %i[email]` keeps attributes visible in the admin UI but out of MCP
  reads, listings and field selection.
- `MCP_EXPOSED = false` leaves the dashboard out of the MCP registry entirely.
- Namespaced models work through the dashboard's own `self.model`, as in Administrate.
- `MCP_BASE_SCOPE` replaces the model's default scope for MCP reads, mirroring an admin controller's
  `scoped_resource`.
- `COLLECTION_FILTERS` are published as filters; a one-argument lambda is a boolean filter, a
  two-argument one takes a value. Foreign key columns are filterable without being declared.
- `mcp_action` publishes one tool per declaration, named `<resource>_<action>` (`order_refund`). It
  requires the OAuth `write` scope, and the authorization predicate (`refund?` by default, or
  `predicate:`, also spelled `pundit:`), checked through `config.authorization`. Every call is
  reported to `config.on_tool_call`, and a result answering `success? == false` is reported as an
  error, with the result's `error` as the message when it has one.
  - A member action (`on: :member`, the default) takes an `id` (or slug), loads the record and checks
    the predicate against it. The block receives `record:`, `admin:` and `params:`.
  - A collection action (`on: :collection`) takes no `id` and loads nothing, so it suits creating a
    record or preparing something that is not a record yet. The predicate, `create?` by default, is
    checked against the model class, both when the tool list is built and on every call. The block
    receives `admin:` and `params:`. When it returns an Active Record object, the response carries
    that record's `id`, so the client can act on what it just created.

## Search

The `admin_resource_list` tool's `query` argument matches exactly by default, so searching for an id
or a slug does not also match every row that merely contains it. `*` is the only wildcard. Every
comparison casts the column to text first, so a search term matched against a uuid `id` column
returns no rows instead of raising an error.

Search is implemented by `FastSearch`, a subclass of `Administrate::Search` that calls methods that
class treats as internal (`search_attributes`, `searchable_fields`, `query_table_name`,
`column_to_query`). That is why the gemspec pins `administrate` below 2.0.
