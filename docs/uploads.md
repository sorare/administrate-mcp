# Presigned uploads

[Back to README](../README.md)

A client such as Claude Code can upload a file and set it on an attachment attribute through an
action, without the file passing through the MCP server:

1. The client calls `uploads_prepare` with the action's `tool` name, the `attribute` and `files`,
   an object of filename to size in bytes, or to `{ "size": ..., "checksum": ... }` where the
   checksum is the base64-encoded MD5 digest of the file (`openssl md5 -binary logo.png | base64`).
   A storage that signs the checksum, such as the Active Storage one, requires it. Each file gets back an `upload_id`, a `method`, a `url`
   and the `fields` (for a `POST`) or `headers` (for a `PUT`) to send.
2. The client uploads each file. With the Shrine storage that is a multipart `POST` carrying every
   field, then the file:
   `curl -F key=... -F policy=... -F file=@logo.png "<url>"`. With the Active Storage storage it is
   a `PUT` of the file with every header:
   `curl -X PUT -H "Content-Type: image/png" -H "Content-MD5: ..." --data-binary @logo.png "<url>"`.
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

Out of the box, `Administrate::Field::Shrine` is the only field mapped to `:attachment`. An Active
Storage dashboard gets no upload param until its field is registered as `:attachment`; see
[Active Storage](#active-storage).

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
| `storage`               | Shrine, else Active Storage | Where files are uploaded; see below                                  |
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
- the file's real size is at most the maximum. The Shrine storage's presigned `POST` already makes
  the storage refuse a larger file, and the Active Storage storage signs the exact declared size and
  checksum; the size is read again before any content is;
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

The uploaded objects and their checked copies are not deleted by the engine. With Shrine, give the
bucket a lifecycle rule that expires the cache prefix after a period longer than `batch_ttl`. Shrine
copies the file from the cache to its permanent storage when it promotes it. With Active Storage,
every prepared file leaves an unattached blob; purge unattached blobs older than `batch_ttl` on a
schedule, as for any direct upload. A copy that failed a check, a source above the maximum size and
the copy that lost a concurrent resolve are purged at once.

```ruby
ActiveStorage::Blob.unattached.where(created_at: ...2.hours.ago).find_each(&:purge_later)
```

## Storage

When Shrine is loaded, the default storage is the Shrine storage. Otherwise, when Active Storage is
loaded, it is the Active Storage storage. Set `config.uploads.storage` to choose another.

### Shrine

`Administrate::MCP::Uploads::ShrineStorage` presigns a `POST` on `Shrine.storages[:cache]` with a
policy bounding the content length, and copies an uploaded object to a fresh key before checking
it. On S3 the copy is server side.

- The storage must be able to presign: `Shrine::Storage::S3` can, `FileSystem` and `Memory`
  cannot, and `uploads_prepare` answers with an error naming the storage.
- The content type comes from the uploader's own metadata extraction, so load Shrine's
  `determine_mime_type` plugin. Without it the type is unknown and every upload is refused.
  Plugins such as `store_dimensions` add their metadata too.
- Pass a different uploader or storage with
  `c.uploads.storage = Administrate::MCP::Uploads::ShrineStorage.new(uploader: 'ImageUploader', storage_key: :cache)`.
  The uploader is a class or a class name.

### Active Storage

`Administrate::MCP::Uploads::ActiveStorageStorage` uses Active Storage direct uploads. Preparing a
file creates a blob with its declared byte size and checksum and presigns a `PUT` for them, so the
service refuses any other size or content: S3 signs `Content-Length` and `Content-MD5`, and the
Disk service's controller compares both. Every file therefore needs a `checksum`.

Resolving copies the uploaded object to a new key with the service's `compose`, reads the copy's
content type from its first bytes (magic numbers only, never the filename), and creates a blob for
the copy. A copy that fails a check is purged, and so is a source blob above the maximum size, which
is not copied. The action receives that blob's signed id, which an attachment accepts:

```ruby
mcp_action :replace_manual, uploads: [:manual], description: 'Replace the manual.' do |record:, params:, **|
  record.update!(manual: params[:manual])
end
```

Register the dashboard's Active Storage field as `:attachment` so `uploads:` accepts it, for
example the field from `administrate-field-active_storage`:

```ruby
Administrate::MCP.configure do |c|
  c.register_field('Administrate::Field::ActiveStorage', as: :attachment)
  c.uploads.enabled = true
  c.uploads.storage = Administrate::MCP::Uploads::ActiveStorageStorage.new(service_name: :amazon)
end
```

- `service_name:` picks a service from `config/storage.yml`; the default is
  `ActiveStorage::Blob.service`.
- The Disk service presigns a URL to the host's own `/rails/active_storage/disk` route, which needs
  URL options that an MCP request does not set. Pass them, as in
  `ActiveStorageStorage.new(url_options: { host: 'admin.example.com', protocol: 'https' })`; without
  them the storage reports that it cannot presign. Use Disk for development only.
- The storage is only loaded when it is used, and the gem does not depend on Active Storage.

### Your own storage

The gem does not depend on Shrine, Active Storage or the AWS SDK. A host can set `storage` to any
object answering:

```ruby
class MyStorage
  def presignable? = true
  def description = 'my storage'

  # Optional. When true, uploads_prepare refuses a file without a checksum.
  def checksum_required? = true

  # => { method: 'POST', url: 'https://...', fields: { ... } }
  #    or { method: 'PUT', url: 'https://...', headers: { 'Content-Type' => content_type } }
  #    The storage should refuse a file above max_size. size and checksum are what the client
  #    declared; checksum is nil when it gave none.
  def presign(key, content_type:, max_size:, expires_in:, filename:, size:, checksum:); end

  # => nil when nothing was uploaded under key, otherwise an object answering mime_type, size
  #    and value (what the action receives as params[:<attribute>]). Copy the object to a key the
  #    client cannot write to and describe the copy. When it is above max_size, return its size and
  #    a value delete accepts without reading the content.
  def fetch(key, filename:, max_size:); end

  # Deletes the copy behind a value fetch returned, when it failed a check or lost a race.
  def delete(value); end
end
```
