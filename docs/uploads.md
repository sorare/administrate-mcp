# Presigned uploads

[Back to README](../README.md)

A client such as Claude Code can upload a file and set it on an attachment attribute through an
action, without the file passing through the MCP server:

1. The client calls `uploads_prepare` with `files`, an object of filename to size in bytes. Each
   file gets back an `upload_id`, a presigned `url` and the `headers` to send with it.
2. The client uploads each file with an HTTP `PUT` to its `url`, sending every header:
   `curl -X PUT -H "Content-Type: image/png" --upload-file logo.png "<url>"`.
3. The client calls an action declared with `uploads: true`, passing `<attribute>_upload_id`. The
   engine resolves it into the attachment value, and the action's block receives it as
   `params[:<attribute>]`.

```ruby
class ArticleDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = { title: Field::String, cover: Field::Shrine }.freeze

  mcp_action :publish, on: :collection, uploads: true,
                       description: 'Publish an article.',
                       params: { title: 'The title.' } do |admin:, params:|
    Articles::Publish.call(admin:, title: params[:title], cover: params[:cover])
  end
end
```

`uploads: true` publishes an optional `<attribute>_upload_id` param for every attribute whose
field is serialized as `:attachment`: `Administrate::Field::Shrine`, or any field class registered
with `register_field(..., as: :attachment)`. `uploads: %i[cover]` limits it to the attributes
listed, and an attribute that is not an attachment raises when the tools are built. A call
without the param leaves `params[:<attribute>]` unset.

## Enabling

```ruby
Administrate::MCP.configure do |c|
  c.uploads.enabled = true
end
```

Uploads need the `administrate_mcp_upload_batches` table, created by the engine's migrations
(`bin/rails administrate_mcp:install:migrations`). While `enabled` is `false`, the default,
`uploads_prepare` is not published, actions publish no upload param, and the table is never used.

`uploads_prepare` requires the OAuth `write` scope and the `default_required_roles`. It only hands
out URLs; setting the file still goes through an action and its own authorization.

| Setting                 | Default                               | Meaning                                                                       |
| ----------------------- | ------------------------------------- | ----------------------------------------------------------------------------- |
| `enabled`               | `false`                               | Publish `uploads_prepare` and the upload params                               |
| `storage`               | the Shrine `:cache` storage           | Where files are uploaded; see below                                           |
| `allowed_content_types` | png, jpg, jpeg, webp                  | File extension (with the dot) to content type                                 |
| `max_size`              | 10 MB                                 | Largest file in bytes, checked on the declared size and again on the real one |
| `url_ttl`               | 15 minutes                            | How long a presigned URL is valid, in seconds                                 |
| `batch_ttl`             | 1 hour                                | How long an `upload_id` can be resolved, in seconds                           |

## Checks

`uploads_prepare` refuses a file whose extension is not allowed or whose declared size is above
`max_size`, and records nothing in that case.

Resolving an `upload_id` checks that:

- it was handed out to the calling admin. Another admin's `upload_id` is answered as not found;
- its batch has not expired;
- the file was uploaded;
- the file's real content type, read from its content, is allowed, whatever its extension;
- the file's real size is at most `max_size`. A presigned `PUT` does not sign `Content-Length`, so
  the storage accepts a file of any size and this is the only place the limit holds.

A failed check is a tool error and the action's block does not run.

## Storage

When Shrine is loaded, the default storage is `Administrate::MCP::Uploads::ShrineStorage`, which
presigns a `PUT` on `Shrine.storages[:cache]` and resolves an `upload_id` into the cached file's
data hash. Assigning that hash to an attachment uses the cached file as it is, without a copy.

- The storage must be able to presign: `Shrine::Storage::S3` can, `FileSystem` and `Memory`
  cannot, and `uploads_prepare` answers with an error naming the storage.
- The content type comes from the uploader's own metadata extraction, so load Shrine's
  `determine_mime_type` plugin. Without it the type is unknown and every upload is refused.
  Plugins such as `store_dimensions` add their metadata too.
- Pass a different uploader or storage with
  `c.uploads.storage = Administrate::MCP::Uploads::ShrineStorage.new(uploader: 'ImageUploader', storage_key: :cache)`.
  The uploader is a class or a class name.
- Neither flow deletes the cached objects: an abandoned upload stays, and so does the cached copy
  once Shrine promotes it. Give the bucket a lifecycle rule that expires the cache prefix after a
  period longer than `batch_ttl`.

The gem does not depend on Shrine or the AWS SDK. A host without Shrine sets `storage` to an object
answering:

```ruby
class MyStorage
  def presignable? = true
  def description = 'my storage'

  # => { url: 'https://...', headers: { 'Content-Type' => content_type } }
  def presign(key, content_type:, expires_in:); end

  # => nil when nothing was uploaded under key, otherwise an object answering
  #    mime_type, size and value (what the action receives as params[:<attribute>])
  def fetch(key, filename:); end
end
```
