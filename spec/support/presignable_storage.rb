# frozen_string_literal: true

require 'shrine/storage/s3'

# Swaps the Shrine cache storage for an S3 storage whose client is stubbed, so presigning works
# and uploaded objects live in a hash. Shrine subclasses keep their own copy of `storages`, so the
# uploader is swapped too.
RSpec.shared_context 'with presignable storage' do
  let(:png) do
    Base64.decode64('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==')
  end
  let(:cache_storage) do
    Shrine::Storage::S3.new(bucket: 'uploads-test', region: 'eu-west-1', prefix: 'cache',
                            access_key_id: 'test', secret_access_key: 'test', stub_responses: true)
  end
  let(:stored_objects) { {} }
  let(:swapped_uploaders) { [Shrine, PictureUploader].index_with { |uploader| uploader.storages[:cache] } }

  before do
    objects = stored_objects
    client = cache_storage.client
    client.stub_responses(:put_object, lambda { |context|
      body = context.params[:body]
      objects[context.params[:key]] = body.respond_to?(:read) ? body.read : body
      {}
    })
    client.stub_responses(:head_object, lambda { |context|
      body = objects[context.params[:key]]
      body ? { content_length: body.bytesize } : { status_code: 404, headers: {}, body: '' }
    })
    client.stub_responses(:copy_object, lambda { |context|
      source = CGI.unescape(context.params[:copy_source].delete_prefix("#{context.params[:bucket]}/"))
      objects[context.params[:key]] = objects.fetch(source)
      { copy_object_result: { etag: '"copied"' } }
    })
    client.stub_responses(:delete_object, lambda { |context|
      objects.delete(context.params[:key])
      {}
    })
    client.stub_responses(:get_object, lambda { |context|
      body = objects[context.params[:key]]
      body ? { body:, content_length: body.bytesize } : 'NoSuchKey'
    })
    swapped_uploaders.each_key { |uploader| uploader.storages[:cache] = cache_storage }
    Administrate::MCP.config.uploads.enabled = true
    Administrate::MCP::Actions.reset!
  end

  after do
    swapped_uploaders.each { |uploader, storage| uploader.storages[:cache] = storage }
    Administrate::MCP::Actions.reset!
  end

  def put_object(key, body)
    stored_objects["cache/#{key}"] = body
  end

  def prepare_upload(files = { 'logo.png' => 1024 }, admin: self.admin, tool: 'widget_create_draft',
                     attribute: 'picture', scopes: ['write'])
    Administrate::MCP::Uploads.prepare(admin:, scopes:, tool:, attribute:, files:)
  end

  def upload_png(**)
    upload_id = prepare_upload({ 'logo.png' => png.bytesize }, **)['logo.png'][:upload_id]
    put_object("#{upload_id}.png", png)
    upload_id
  end
end
