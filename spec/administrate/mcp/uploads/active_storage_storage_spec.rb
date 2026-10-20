# frozen_string_literal: true

RSpec.describe Administrate::MCP::Uploads::ActiveStorageStorage do
  let(:url_options) { { host: 'admin.example.com', protocol: 'https' } }
  let(:storage) { described_class.new(url_options:) }
  let(:admin) { create(:admin, :full_access) }
  let(:gadget) { create(:gadget) }
  let(:ctx) { { admin:, scopes: ['write'] } }
  let(:png) do
    Base64.decode64('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==')
  end
  let(:rules) { Administrate::MCP.config.uploads.rules }
  let(:replace_manual) do
    dashboard = stub_const('GadgetManualDashboard', Class.new(Administrate::BaseDashboard))
    dashboard.const_set(:ATTRIBUTE_TYPES, { label: Administrate::Field::String, manual: PictureField }.freeze)
    spec = Administrate::MCP::Actions.build_spec(:replace_manual, description: 'Replace the manual', uploads: true) do
      |record:, params:, **|
      record.update!(manual: params[:manual])
    end
    uploads = Administrate::MCP::Uploads::Declarations.action_attributes(dashboard, :replace_manual, spec[:uploads])
    definition = Administrate::MCP::Actions::Definition.new(model_class: Gadget, **spec, uploads:)
    allow(Administrate::MCP::Actions).to(receive(:definitions).and_wrap_original { |all| all.call + [definition] })
    Administrate::MCP::Actions::ToolFactory.build(definition)
  end

  before do
    FileUtils.rm_rf(ActiveStorage::Blob.service.root)
    Administrate::MCP.config.uploads.enabled = true
    Administrate::MCP.config.uploads.storage = storage
    Administrate::MCP::Actions.reset!
    replace_manual
  end

  after { Administrate::MCP::Actions.reset! }

  def stored_files
    Dir[File.join(ActiveStorage::Blob.service.root, '**', '*')].select { |path| File.file?(path) }
  end

  def checksum(body)
    Digest::MD5.base64digest(body)
  end

  def prepare(files = { 'manual.png' => { size: png.bytesize, checksum: checksum(png) } })
    Administrate::MCP::Uploads.prepare(admin:, scopes: ['write'], tool: 'gadget_replace_manual', attribute: 'manual',
                                       files:)
  end

  def put_file(upload, body)
    Rack::MockRequest.new(Rails.application)
                     .put(upload[:url], input: body, 'CONTENT_TYPE' => upload[:headers]['Content-Type'])
  end

  def resolve(upload_id, with: rules)
    Administrate::MCP::Uploads.resolve(admin:, upload_id:, tool: 'gadget_replace_manual', attribute: 'manual',
                                       rules: with)
  end

  def upload_png
    upload = prepare['manual.png']
    put_file(upload, png)
    upload[:upload_id]
  end

  describe 'preparing' do
    it 'creates a blob for the declared size and checksum and signs a PUT for it' do
      upload = prepare['manual.png']

      expect(upload).to include(method: 'PUT', headers: { 'Content-Type' => 'image/png' })
      expect(upload[:url]).to start_with('https://admin.example.com/rails/active_storage/disk/')
      expect(ActiveStorage::Blob.sole).to have_attributes(key: "#{upload[:upload_id]}.png", filename: 'manual.png',
                                                          byte_size: png.bytesize, checksum: checksum(png),
                                                          content_type: 'image/png')
    end

    it 'requires a checksum for every file' do
      expect { prepare({ 'manual.png' => png.bytesize }) }.to raise_error(
        Administrate::MCP::InvalidArgumentError,
        /manual.png needs a checksum, the base64-encoded MD5 digest of the file, because Active Storage service :test/
      )
      expect(ActiveStorage::Blob.count).to eq(0)
      expect(Administrate::MCP::UploadBatch.count).to eq(0)
    end

    it 'refuses a checksum that is not a base64 MD5 digest' do
      expect { prepare({ 'manual.png' => { size: png.bytesize, checksum: 'not-a-digest' } }) }
        .to raise_error(Administrate::MCP::InvalidArgumentError, /checksum must be the base64-encoded MD5 digest/)
    end

    it 'cannot presign on a Disk service without URL options' do
      Administrate::MCP.config.uploads.storage = described_class.new

      expect { prepare }.to raise_error(
        Administrate::MCP::ConfigurationError,
        /Active Storage service :test \(ActiveStorage::Service::DiskService\) cannot presign uploads/
      )
    end
  end

  describe 'uploading' do
    it 'accepts the declared file' do
      expect(put_file(prepare['manual.png'], png).status).to eq(204)
    end

    it 'refuses a file of another size' do
      upload = prepare['manual.png']

      expect(put_file(upload, "#{png}extra").status).to eq(422)
      expect { resolve(upload[:upload_id]) }
        .to raise_error(Administrate::MCP::InvalidArgumentError, /has not been uploaded yet/)
    end

    it 'refuses other content of the declared size' do
      upload = prepare['manual.png']

      expect(put_file(upload, png.reverse).status).to eq(422)
      expect { resolve(upload[:upload_id]) }
        .to raise_error(Administrate::MCP::InvalidArgumentError, /has not been uploaded yet/)
    end
  end

  describe 'resolving' do
    it 'returns the signed id of a checked copy' do
      upload_id = upload_png

      blob = ActiveStorage::Blob.find_signed!(resolve(upload_id))

      expect(blob.key).not_to eq("#{upload_id}.png")
      expect(blob).to have_attributes(filename: 'manual.png', byte_size: png.bytesize, checksum: checksum(png),
                                      content_type: 'image/png', identified: true)
      expect(blob.download).to eq(png)
    end

    it 'checks the content type from the content, whatever the extension' do
      html = '<html><body><script>alert(1)</script></body></html>'
      upload = prepare({ 'manual.png' => { size: html.bytesize, checksum: checksum(html) } })['manual.png']
      put_file(upload, html)

      expect { resolve(upload[:upload_id]) }
        .to raise_error(Administrate::MCP::InvalidArgumentError, %r{is text/html, expected one of image/png})
      expect(ActiveStorage::Blob.pluck(:key)).to eq(["#{upload[:upload_id]}.png"])
      expect(stored_files.size).to eq(1)
    end

    it 'keeps the checked copy when the uploaded object changes afterwards' do
      upload_id = upload_png
      blob = ActiveStorage::Blob.find_signed!(resolve(upload_id))

      ActiveStorage::Blob.service.upload("#{upload_id}.png", StringIO.new('replaced'))

      expect(blob.download).to eq(png)
    end

    it 'refuses a declared size above the maximum without copying, and purges the upload' do
      upload_id = upload_png

      expect { resolve(upload_id, with: rules.with(max_size: 10)) }
        .to raise_error(Administrate::MCP::InvalidArgumentError, /is #{png.bytesize} bytes, the maximum is 10/)
      expect(ActiveStorage::Blob.count).to eq(0)
      expect(ActiveStorage::Blob.service.exist?("#{upload_id}.png")).to be(false)
    end

    it 'returns the value another call recorded meanwhile, and purges its own copy' do
      upload_id = upload_png
      winner = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(png), filename: 'winner.png')
      allow(storage).to receive(:fetch).and_wrap_original do |original, *args, **kwargs|
        original.call(*args, **kwargs).tap do
          Administrate::MCP::UploadBatch.sole.record_value!(upload_id, winner.signed_id)
        end
      end

      expect(resolve(upload_id)).to eq(winner.signed_id)
      expect(ActiveStorage::Blob.pluck(:key)).to contain_exactly("#{upload_id}.png", winner.key)
    end
  end

  it 'attaches the uploaded file through an action' do
    result = replace_manual.call(id: gadget.id, manual_upload_id: upload_png, server_context: ctx)

    expect(result.error?).to be(false)
    manual = gadget.reload.manual
    expect(manual).to be_attached
    expect(manual.blob).to have_attributes(filename: 'manual.png', content_type: 'image/png')
    expect(manual.download).to eq(png)
  end

  it 'is the default storage when Active Storage is loaded and Shrine is not' do
    hide_const('Shrine')
    Administrate::MCP.config.uploads.storage = nil

    expect(Administrate::MCP.config.uploads.storage).to be_a(described_class)
  end
end
