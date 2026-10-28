# Tool views

A tool view is an interactive page an MCP client renders in place of a tool's raw result. The
engine implements the server side of the [MCP Apps extension](https://github.com/modelcontextprotocol/ext-apps)
(SEP-1865): a view is a `ui://` HTML resource, a tool names the view that renders it in its `_meta`,
and a client that supports the extension fetches the view with `resources/read` and shows it next
to the conversation. A client without the extension ignores all of it and reads the tool's text
result as before.

Views are off until the host turns them on:

```ruby
Administrate::MCP.configure do |config|
  config.tool_views = true
end
```

Nothing a tool returns changes for the model: the text content stays the same. A view receives the
full result, including a `_meta` entry the host keeps out of the model's context.

## Built-in views

| View | URI | Tools | What it does |
| --- | --- | --- | --- |
| Resource | `ui://<server-name>/resource` | `admin_resource_list`, `admin_resource_show`, every `mcp_action` | A table of records with paging, sorting and search, a record page, and links that follow `belongs_to` and `has_many` associations to other registered resources. For an action, a confirmation, the data the action returned, and the record it saved |
| Sidekiq | `ui://<server-name>/sidekiq` | `sidekiq_stats`, `sidekiq_retries` | Counts per job class and per queue, the first page of retries, and a refresh button |

`<server-name>` is `config.server_name` with underscores turned into dashes.

The resource view needs nothing from a dashboard. `admin_resource_list` and `admin_resource_show`
add, when views are on, a `_meta["administrate-mcp/view"]` entry to their result: the resource name
and, per returned field, its kind (`belongs_to`, `has_many`, `datetime`, `enum`, `attachment`, `url`,
`scalar`, ...) and, for an association to a registered resource, that resource's name and the
foreign key a filtered list of it takes. Paging, sorting, search and following an association are
ordinary `tools/call` requests the client makes on the view's behalf, so they go through the same
authentication, authorization and `on_tool_call` audit as a call the model makes. A client that does
not proxy tool calls gets a read-only table whose rows open the record's admin page.

An `mcp_action` renders in the resource view unless it declares `view:`. The view shows the
action's outcome and the data it returned, then loads the record whose `id` the answer carries with
`admin_resource_show`, so an uploaded picture or a computed field is on screen right after the write.
A failed action shows its error message.

When the person moves to another page of the view, the view tells the client which records are on
screen (`ui/update-model-context`), so the next answer is about what the person is looking at. It
names them by resource and id only. Record text such as a name, and the person's search terms, stay
out of it: a model reads that context as coming from the client, and record text is written by
whoever owns the record.

The field hints name an associated resource only when the caller can list it, as
`admin_resource_list_resources` does.

Only `Field::Url` fields, attachments and the record's own admin link become links. A text field
that happens to hold a URL stays text, as on the admin show page, since end users write many of
those fields.

## Images and other external content

A client renders a view under a Content Security Policy that, by default, loads nothing from another
origin. An attachment field whose URL points at your storage shows as a link until the origin is
declared:

```ruby
config.tool_view_csp = { resource_domains: ['https://uploads.example.com'] }
```

The keys are `resource_domains` (images, media, fonts, stylesheets, scripts), `connect_domains`
(`fetch` and WebSocket), `frame_domains` and `base_uri_domains`. Any other key raises when a view is
read. The client may still refuse an origin.

## A view of your own

A view is a subclass of `Administrate::MCP::ToolView` that names a script and, optionally, a
stylesheet:

```ruby
# app/mcp_views/review_queue_view.rb
class ReviewQueueView < Administrate::MCP::ToolView
  title 'Review queue'
  description 'The open reviews, with approve and reject buttons.'
  script Rails.root.join('app/mcp_views/review_queue.js')
  stylesheet Rails.root.join('app/mcp_views/review_queue.css')
end
```

The view's name, used in its URI, is the class name without `View`, underscored (`review_queue`);
`view_name 'queue'` overrides it.

Link a tool to it with `tool_view`, or an action with `view:`:

```ruby
class ReviewQueueTool < Administrate::MCP::BaseTool
  tool_name 'review_queue'
  tool_view ReviewQueueView
end

mcp_action :approve, description: 'Approve a review.', view: 'ReviewQueueView' do |record:, **|
  record.approve!
end
```

`tool_view` takes `visibility: %i[app]` for a tool only the view calls, which a client that supports
the extension keeps out of the model's tool list. It is not access control: a client without the
extension lists and calls the tool like any other, so the tool must run every check a model call
would need, and it does, since it is an ordinary tool on the server.

The engine wraps the script in an HTML document with a shared runtime, `window.AdministrateMCP`:

| Member | Does |
| --- | --- |
| `connect()` | Runs the `ui/initialize` handshake. Call it once, after registering handlers |
| `on('input' \| 'result' \| 'cancelled' \| 'context' \| 'teardown', callback)` | Registers a handler; `input` and `result` replay the last value to a late handler |
| `resultData(result)` | The result's `structuredContent`, or its JSON text content parsed |
| `resultError(result)` | The error message of a failed result, or `null` |
| `resultMeta(result, key)` | One entry of the result's `_meta` |
| `callTool(name, args)` | Calls a tool on this server through the client |
| `canCallTools()` | Whether the client proxies tool calls |
| `toolName()` | The name of the tool whose result the view is showing, when the client says |
| `openLink(url)`, `sendMessage(text)`, `updateModelContext(text)`, `requestDisplayMode(mode)` | The extension's `ui/open-link`, `ui/message`, `ui/update-model-context` and `ui/request-display-mode` |
| `h(tag, attributes, ...children)`, `mount(node)`, `link(url, label)`, `message(text, className)`, `formatDate(value)` | DOM helpers that set text, never markup |

The runtime reports the view's size to the client as it changes, and applies the client's theme
and CSS variables. The stylesheet it ships defines `--am-*` custom properties from those variables,
with light and dark fallbacks, for a view's own stylesheet to use.

A view renders admin data. Build its DOM with `h` or `textContent`, never `innerHTML`, so a record
cannot inject markup into the page. `h` only attaches functions as event handlers, and drops an
`href`, `src` or other URL attribute that is not `http` or `https`; `openLink` refuses the same
URLs. Keep record text out of `updateModelContext` and `sendMessage`: refer to records by id.

## Asking for a view

`report_mcp_improvement` has a `missing_view` category for a result the person needed to browse,
compare or act on, and that read badly as text. Reports in it are the list of views worth building
next.
