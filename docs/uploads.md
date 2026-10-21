# Presigned uploads

[Back to README](../README.md)

A client such as Claude Code can upload a file and set it on an attachment attribute through an
action, without the file passing through the MCP server:

1. The client calls `uploads_prepare` with the action's `tool` name, the `attribute` and `files`,
   an object of filename to size in bytes. Each file gets back an `upload_id`, a `method`, a `url`
   and the `fields` (for a `POST`) or `headers` (for a `PUT`) to send.
2. The client uploads each file. With the default storage that is a multipart `POST` carrying every
   field, then the file:
   `curl -F key=... -F policy=... -F file=@logo.png "<url>"`.
3. The client calls the action with `<attribute>_upload_id`. The engine resolves it into the
   attachment value, and the action's block receives it as `params[:<attribute>]`.

```ruby
class ArticleDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = { title: Field::String, cover: Field::Shrine, contract: Field::Shrine }.freeze

  mcp_action :publish, on: :collection, predicate: :create?, destructive: false,
                       uploads: {
                         cover: {},
                         contract: { content_types: { '.pdf' => 'application/pdf' }, max_size: 5 * 1024 * 1024 }
                       },
                       description: 'Publish an article.',
                       params: { title: 'The title.' } do |admin:, params:|
    Articles::Publish.call(admin:, **params.slice(:title, :cover, :contract)).article
  end
end
```

`uploads:` takes:

- `true`, for every attribute whose field is serialized as `:attachment`:
  `Administrate::Field::Shrine`, or any field class registered with
  `register_field(..., as: :attachment)`. It raises when the dashboard has none.
- a list of attributes, such as `%i[cover]`.
- a hash of attribute to `content_types:` (extension to content type, like
  `allowed_content_types`) and `max_size:`, which override the defaults for that attribute.

An attribute that is not an attachment raises when the tools are built. So does a rule other than
`content_types:` and `max_size:`, a `content_types:` that is not a hash of `.ext` keys, or a
`max_size:` that is not a positive integer. A call without the param leaves `params[:<attribute>]`
unset.

Out of the box, uploads work with Shrine: `Administrate::Field::Shrine` is the only field mapped to
`:attachment` by default, and the default storage is a Shrine storage. An Active Storage dashboard
gets no upload param until its field is registered as `:attachment` and `config.uploads.storage` is
set to a storage for it.

## Enabling

```ruby
Administrate::MCP.configure do |c|
  c.uploads.enabled = true
end
```

Uploads need the `administrate_mcp_upload_batches` table, created by the engine's migrations
(`bin/rails administrate_mcp:install:migrations`). While `enabled` is `false`, the default,
`uploads_prepare` is not published, actions publish no upload param, and the table is never used.

| Setting                 | Default                     | Meaning                                                              |
| ----------------------- | --------------------------- | -------------------------------------------------------------------- |
| `enabled`               | `false`                     | Publish `uploads_prepare` and the upload params                      |
| `storage`               | the Shrine `:cache` storage | Where files are uploaded; see below                                  |
| `allowed_content_types` | png, jpg, jpeg, webp        | Default file extension (with the dot) to content type                |
| `max_size`              | 10 MB                       | Default largest file in bytes                                        |
| `max_files`             | 10                          | Most files one `uploads_prepare` call can prepare                    |
| `url_ttl`               | 15 minutes                  | How long a presigned URL is valid, in seconds                        |
| `batch_ttl`             | 1 hour                      | How long an `upload_id` can be resolved, in seconds                  |

Do not allow `image/svg+xml`, `text/html` or another type a browser runs. The object is served from
the bucket with that type, so such a file is stored cross-site scripting for anyone who opens it.

## Checks

`uploads_prepare` requires the OAuth `write` scope and the `default_required_roles`, and is only
published to a caller who can use an action that accepts uploads. It refuses the call unless the
named action exists, accepts an upload for the named attribute, and is available to the caller: its
scope is granted and its predicate passes, the same check that decides whether the action is
listed. It also refuses a file whose extension
is not allowed for that attribute, a declared size above its maximum, and more than `max_files`
files, and records nothing in that case.

Resolving an `upload_id` checks that:

- it was handed out to the calling admin. Another admin's `upload_id` is answered as not found;
- it was prepared for this action and attribute;
- its batch has not expired;
- the file was uploaded;
- the file's real size is at most the maximum. The default storage's presigned `POST` already makes
  the storage refuse a larger file; the size is read again before any content is;
- the file's real content type, read from its content, is allowed, whatever its extension.

The checks run on a copy of the uploaded object, under a key no presigned URL points to, and the
action receives that copy. Uploading again to the same URL afterwards changes nothing that was
checked. A copy that fails a check is deleted. The checked copy is remembered: passing the same
`upload_id` again, for example after the action failed on another param, returns it without a new
upload. The storage is read outside any database transaction; only recording the checked copy
locks the batch row, and if two calls race, the first recorded copy wins and the other is deleted.

A failed check is a tool error and the action's block does not run.

## Clean-up

Expired batches stay in the table until removed. Call `Administrate::MCP::CleanExpiredUploadBatches`
from your scheduler; it deletes up to 10,000 expired batches per call and reports `more?` when there
may be others:

```ruby
loop { break unless Administrate::MCP::CleanExpiredUploadBatches.call.more? }
```

The uploaded objects and their checked copies are not deleted by the engine. Give the bucket a
lifecycle rule that expires the cache prefix after a period longer than `batch_ttl`. Shrine copies
the file from the cache to its permanent storage when it promotes it.

## Storage

When Shrine is loaded, the default storage is `Administrate::MCP::Uploads::ShrineStorage`, which
presigns a `POST` on `Shrine.storages[:cache]` with a policy bounding the content length, and copies
an uploaded object to a fresh key before checking it. On S3 the copy is server side.

- The storage must be able to presign: `Shrine::Storage::S3` can, `FileSystem` and `Memory`
  cannot, and `uploads_prepare` answers with an error naming the storage.
- The content type comes from the uploader's own metadata extraction, so load Shrine's
  `determine_mime_type` plugin. Without it the type is unknown and every upload is refused.
  Plugins such as `store_dimensions` add their metadata too.
- Pass a different uploader or storage with
  `c.uploads.storage = Administrate::MCP::Uploads::ShrineStorage.new(uploader: 'ImageUploader', storage_key: :cache)`.
  The uploader is a class or a class name.

The gem does not depend on Shrine or the AWS SDK. A host without Shrine sets `storage` to an object
answering:

```ruby
class MyStorage
  def presignable? = true
  def description = 'my storage'

  # => { method: 'POST', url: 'https://...', fields: { ... } }
  #    or { method: 'PUT', url: 'https://...', headers: { 'Content-Type' => content_type } }
  #    The storage should refuse a file above max_size.
  def presign(key, content_type:, max_size:, expires_in:); end

  # => nil when nothing was uploaded under key, otherwise an object answering mime_type, size
  #    and value (what the action receives as params[:<attribute>]). Copy the object to a key the
  #    client cannot write to and describe the copy, and when it is above max_size, return its size
  #    without reading the content.
  def fetch(key, filename:, max_size:); end

  # Deletes the copy behind a value fetch returned, when it failed a check or lost a race.
  def delete(value); end
end
```
