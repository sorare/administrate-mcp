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
- `mcp_action` publishes one tool per declaration. It requires the OAuth `write` scope, and the
  authorization predicate (`refund?` by default, or `predicate:`) on the loaded record. The block
  receives `record:`, `admin:` and `params:`; a result answering `success? == false` is reported as
  an error.
