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
             destructive: false,
             description: 'Import an order from a marketplace.',
             params: { reference: 'The marketplace order reference.' } do |admin:, params:|
    Orders::Import.call!(reference: params[:reference], admin:).order
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
  requires the OAuth `write` scope, and the authorization predicate (`refund?` for `:refund` by
  default, or `predicate:`, also spelled `pundit:`), checked through `config.authorization`. Every
  call is reported to `config.on_tool_call`.
  - The input schema lists `params` and closes the object (`additionalProperties: false`), so an
    argument that is not declared is refused before the action runs, and the block only ever sees
    declared params.
  - The block's result decides the answer. A result answering `success? == false` is an error, with
    the result's `error` as the message when it has one. An Active Record object that was never
    saved or has errors is an error too, with its validation messages. So is `false`, the result of
    a failed `update` or of a `destroy` a callback aborted; for a member action the message is the
    loaded record's validation messages when it has any. Anything else is a success, including a
    record the block destroyed. To send data back with the answer, return an
    `Administrate::MCP::ActionResult`; see [Returning data from an action](#returning-data-from-an-action).
  - The tool is announced as destructive unless the declaration says `destructive: false`. Clients
    may ask for confirmation before running a destructive tool, so set it on actions that only add
    or prepare something.
  - A member action (`on: :member`, the default) takes an `id` (or slug), loads the record and checks
    the predicate against it. The block receives `record:`, `admin:` and `params:`. The response
    echoes the `id` the caller passed.
  - A collection action (`on: :collection`) takes no `id` and loads nothing, so it suits creating a
    record or preparing something that is not a record yet. The predicate is checked against a new
    instance of the model, as Administrate does for `new` and `create`, both when the tool list is
    built and on every call; a creating action usually declares `predicate: :create?`. The block
    receives `admin:` and `params:`, and owns any scoping of what it creates, such as a tenant,
    since no record lookup does it. The response carries the primary key of the record the block
    returns, so return the created record for the client to act on it; a block that returns
    something else gets a response without `id`.
  - `uploads:` (`true`, a list of attachment attributes, or per-attribute `content_types:` and
    `max_size:`) adds an optional `<attribute>_upload_id` param for each of them, and the block
    receives the uploaded file as `params[:<attribute>]`. See [Presigned uploads](uploads.md).

## Returning data from an action

An action answers `{ status, model, id, action }` by default, as JSON text and, identically, as the
result's `structuredContent`. When the client needs more than that, such as what an import created
and what it skipped, the block returns an `Administrate::MCP::ActionResult` and the answer gains a
`data` key:

```ruby
mcp_action :import_batch,
           on: :collection,
           description: 'Import orders from a marketplace export.',
           params: { references: { type: 'array', items: { type: 'string' } } } do |admin:, params:|
  report = Orders::ImportBatch.call!(references: params[:references], admin:)
  next Administrate::MCP::ActionResult.failure('No order matched', data: { unknown: report.unknown }) if report.empty?

  Administrate::MCP::ActionResult.success(record: report.batch,
                                          data: { created: report.created.size, unknown: report.unknown })
end
```

```json
{ "status": "ok", "model": "order", "id": 42, "action": "import_batch", "data": { "created": 3, "unknown": ["X-9"] } }
```

- `ActionResult.success(record:, data:)`: `record` is optional and is checked as if the block had
  returned it, so an unsaved or invalid record is still an error, and a collection action still
  answers its `id`.
- `ActionResult.failure(message, data:)` is an error with `message`, or `<action> failed` without
  one. The error's first content block stays the message alone. When there is data, a second block
  carries `{ "error": message, "data": … }` as JSON, and the result's `structuredContent` carries the
  same object, so clients that only read the content still see the data.
- These two are the only constructors. Any result object that answers `mcp_data` with a Hash works
  the same way, so a host's own service result can carry its data without being wrapped; `success?`
  and `error` are read from it as for any other result.
- A plain Hash returned by the block is not sent back, as before: data reaches the client only when
  the block asks for it, never because a service happened to return a Hash.
- `data` must be a Hash of JSON values: Hashes with String or Symbol keys, Arrays, Strings, Symbols,
  Integers, finite Floats, `true`, `false` and `nil`, nested at most 32 levels deep. Strings and
  keys must be valid UTF-8 or convertible to it, so check bytes read from a file. Convert
  anything else, such as a time (`at.iso8601`) or a record (`record.id`), yourself. The engine
  encodes a plain copy it builds from those values, so an object's own `as_json` never runs, and a
  key given both as a String and as a Symbol is refused rather than sent twice. The copy's JSON may
  be at most `config.action_data_max_bytes` (32 KB by default; `nil` removes the limit), so that an
  action cannot fill the client's context. Return counts and the few items the client must act on,
  not every row.
- Data that breaks a rule is answered as an error naming the offending path, for example
  `data.report.rows[1] (Object) is not a JSON value`. The block has already run by then, so the
  message says the action ran: fix the action rather than retrying the call.
- `data` reaches the client as it is, without the protections fields get from
  `skipped_field_classes` and the field serializers. Don't return secrets, tokens or credentials. A
  download URL is a bearer credential that ends up in transcripts and client logs, so make it
  short-lived. Strings that came from end users (names, notes, references) are untrusted text in the
  model's context, as they are in any field.

## Search

The `admin_resource_list` tool's `query` argument matches exactly by default, so searching for an id
or a slug does not also match every row that merely contains it. `*` is the only wildcard. Every
comparison casts the column to text first, so a search term matched against a uuid `id` column
returns no rows instead of raising an error.

Search is implemented by `FastSearch`, a subclass of `Administrate::Search` that calls methods that
class treats as internal (`search_attributes`, `searchable_fields`, `query_table_name`,
`column_to_query`). That is why the gemspec pins `administrate` below 2.0.
