# frozen_string_literal: true

RSpec.describe Administrate::MCP::Uploads do
  include_context 'with presignable storage'

  let(:admin) { create(:admin, :full_access) }
  let(:rules) { Administrate::MCP.config.uploads.rules }

  def entry_for(upload_id)
    Administrate::MCP::UploadBatch.with_upload(upload_id).sole.file(upload_id)
  end

  def post_policy(upload)
    JSON.parse(Base64.decode64(upload[:fields]['policy']))
  end

  describe '.prepare' do
    it 'records the batch and hands out a presigned POST per file' do
      uploads = prepare_upload({ 'logo.png' => 1024, 'banner.JPG' => 2048 })

      expect(uploads.keys).to eq(%w[logo.png banner.JPG])
      expect(uploads['logo.png']).to include(method: 'POST', url: 'https://uploads-test.s3.eu-west-1.amazonaws.com')
      expect(uploads['logo.png'][:fields]).to include('key' => "cache/#{uploads['logo.png'][:upload_id]}.png",
                                                      'Content-Type' => 'image/png')
      expect(uploads['banner.JPG'][:fields]).to include('Content-Type' => 'image/jpeg')

      batch = Administrate::MCP::UploadBatch.sole
      expect(batch).to have_attributes(admin:)
      expect(batch.expires_at).to be_within(5.seconds).of(1.hour.from_now)
      expect(batch.file(uploads['logo.png'][:upload_id])).to include(
        'filename' => 'logo.png', 'content_type' => 'image/png', 'size' => 1024,
        'tool' => 'widget_create_draft', 'attribute' => 'picture'
      )
    end

    it 'bounds the content length in the POST policy, so the storage refuses a larger file' do
      conditions = post_policy(prepare_upload['logo.png'])['conditions']

      expect(conditions).to include(['content-length-range', 1, 10 * 1024 * 1024])
    end

    it 'signs the POST for 15 minutes by default' do
      expiration = Time.zone.parse(post_policy(prepare_upload['logo.png'])['expiration'])

      expect(expiration).to be_within(5.seconds).of(15.minutes.from_now)
    end

    it 'refuses a file type outside the allowed ones and records nothing' do
      expect { prepare_upload({ 'notes.pdf' => 10, 'logo.png' => 10 }) }
        .to raise_error(Administrate::MCP::InvalidArgumentError, /notes\.pdf is not an allowed file type/)
      expect(Administrate::MCP::UploadBatch.count).to eq(0)
    end

    it 'refuses a declared size above the maximum' do
      expect { prepare_upload({ 'logo.png' => (10 * 1024 * 1024) + 1 }) }
        .to raise_error(Administrate::MCP::InvalidArgumentError, /logo\.png size must be between 1 and 10485760 bytes/)
    end

    it 'refuses more files than max_files' do
      Administrate::MCP.config.uploads.max_files = 2

      expect { prepare_upload({ 'a.png' => 1, 'b.png' => 1, 'c.png' => 1 }) }
        .to raise_error(Administrate::MCP::InvalidArgumentError, 'files can name at most 2 files')
    end

    it 'refuses an empty list' do
      expect { prepare_upload({}) }.to raise_error(Administrate::MCP::InvalidArgumentError, /at least one file/)
    end

    it 'refuses an action that does not exist or accepts no upload for the attribute' do
      expect { prepare_upload(tool: 'widget_nope') }
        .to raise_error(Administrate::MCP::InvalidArgumentError, /No action widget_nope .* available to you/)
      expect { prepare_upload(tool: 'gadget_relabel', attribute: 'label') }
        .to raise_error(Administrate::MCP::InvalidArgumentError, /No action gadget_relabel/)
    end

    it 'refuses an action the admin is not authorized to use' do
      Administrate::MCP.config.authorization = Class.new(Administrate::MCP::Authorization::Base) do
        def authorized?(_admin, _record_or_class, action) = action != :create?
      end.new

      expect { prepare_upload }.to raise_error(Administrate::MCP::InvalidArgumentError, /available to you/)
      expect(Administrate::MCP::UploadBatch.count).to eq(0)
    end

    it 'explains a storage that cannot presign' do
      Shrine.storages[:cache] = Shrine::Storage::Memory.new

      expect { prepare_upload }.to raise_error(
        Administrate::MCP::ConfigurationError,
        /Shrine storage :cache \(Shrine::Storage::Memory\) cannot presign uploads/
      )
    end
  end

  describe '.resolve' do
    let(:upload_id) { prepare_upload['logo.png'][:upload_id] }

    def resolve(as: admin, tool: 'widget_create_draft', attribute: 'picture', with: rules)
      described_class.resolve(admin: as, upload_id:, tool:, attribute:, rules: with)
    end

    it 'returns a checked copy of the uploaded file, under a key no URL points to' do
      put_object(entry_for(upload_id)['key'], png)

      value = resolve

      expect(value).to include('storage' => 'cache')
      expect(value['id']).not_to eq("#{upload_id}.png")
      expect(value['id']).to end_with('.png')
      expect(value['metadata']).to eq('filename' => 'logo.png', 'size' => png.bytesize, 'mime_type' => 'image/png')
      expect(stored_objects["cache/#{value['id']}"]).to eq(png)
    end

    it 'keeps the checked content when the client uploads again to the same URL' do
      put_object(entry_for(upload_id)['key'], png)
      value = resolve

      put_object(entry_for(upload_id)['key'], '<html><script>alert(1)</script></html>')

      expect(stored_objects["cache/#{value['id']}"]).to eq(png)
      expect(resolve).to eq(value)
    end

    it 'refuses content whose real type is not allowed, whatever the extension, and deletes the copy' do
      put_object(entry_for(upload_id)['key'], '%PDF-1.4 not an image')

      expect { resolve }.to raise_error(
        Administrate::MCP::InvalidArgumentError,
        "Upload #{upload_id} is application/pdf, expected one of image/png, image/jpeg, image/webp"
      )
      expect(stored_objects.keys).to eq(["cache/#{upload_id}.png"])
    end

    it 'returns the value another call recorded meanwhile, and deletes its own copy' do
      put_object(entry_for(upload_id)['key'], png)
      winner = { 'id' => 'winner.png', 'storage' => 'cache', 'metadata' => {} }
      storage = Administrate::MCP.config.uploads.storage
      allow(Administrate::MCP.config.uploads).to receive(:storage).and_return(storage)
      allow(storage).to receive(:fetch).and_wrap_original do |original, *args, **kwargs|
        original.call(*args, **kwargs).tap do
          Administrate::MCP::UploadBatch.sole.record_value!(upload_id, winner)
        end
      end

      expect(resolve).to eq(winner)
      expect(stored_objects.keys).to eq(["cache/#{upload_id}.png"])
    end

    it 'refuses a real size above the maximum without reading the content' do
      put_object(entry_for(upload_id)['key'], png)
      small = Administrate::MCP.config.uploads.rules(max_size: png.bytesize - 1)
      uploaders = []
      allow(Shrine).to receive(:new).and_wrap_original do |original, *args|
        original.call(*args).tap do |uploader|
          allow(uploader).to receive(:extract_metadata).and_call_original
          uploaders << uploader
        end
      end

      expect { resolve(with: small) }.to raise_error(
        Administrate::MCP::InvalidArgumentError,
        "Upload #{upload_id} is #{png.bytesize} bytes, the maximum is #{png.bytesize - 1}"
      )
      expect(uploaders).not_to be_empty
      uploaders.each { |uploader| expect(uploader).not_to have_received(:extract_metadata) }
      expect(stored_objects.keys).to eq(["cache/#{upload_id}.png"])
    end

    it 'reports a file that was never uploaded' do
      expect { resolve }.to raise_error(Administrate::MCP::InvalidArgumentError, /has not been uploaded yet/)
    end

    it 'refuses an expired batch' do
      put_object(entry_for(upload_id)['key'], png)
      Administrate::MCP::UploadBatch.sole.update!(expires_at: 1.minute.ago)

      expect { resolve }.to raise_error(Administrate::MCP::InvalidArgumentError, /Upload #{upload_id} expired at/)
    end

    it 'refuses an upload prepared for another action or attribute' do
      put_object(entry_for(upload_id)['key'], png)

      expect { resolve(tool: 'gadget_relabel') }.to raise_error(
        Administrate::MCP::InvalidArgumentError, "Upload #{upload_id} was prepared for widget_create_draft picture"
      )
    end

    it "answers another admin's upload as not found" do
      put_object(entry_for(upload_id)['key'], png)

      expect { resolve(as: create(:admin, :full_access)) }
        .to raise_error(Administrate::MCP::InvalidArgumentError, "Upload #{upload_id} not found")
    end

    it 'answers an unknown upload_id as not found' do
      expect do
        described_class.resolve(admin:, upload_id: SecureRandom.uuid, tool: 'widget_create_draft',
                                attribute: 'picture', rules:)
      end.to raise_error(Administrate::MCP::InvalidArgumentError, /not found/)
    end
  end
end
