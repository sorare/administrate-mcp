# frozen_string_literal: true

RSpec.describe Administrate::MCP::Uploads do
  include_context 'with presignable storage'

  let(:admin) { create(:admin, :full_access) }

  def prepare(files = { 'logo.png' => 1024 })
    described_class.prepare(admin:, files:)
  end

  def entry_for(upload_id)
    Administrate::MCP::UploadBatch.with_upload(upload_id).sole.file(upload_id)
  end

  describe '.prepare' do
    it 'records the batch and hands out a presigned PUT per file' do
      uploads = prepare('logo.png' => 1024, 'banner.JPG' => 2048)

      expect(uploads.keys).to eq(%w[logo.png banner.JPG])
      expect(uploads['logo.png']).to include(headers: { 'Content-Type' => 'image/png' })
      expect(uploads['logo.png'][:url]).to start_with('https://uploads-test.s3.eu-west-1.amazonaws.com/cache/')
      expect(uploads['banner.JPG'][:headers]).to eq('Content-Type' => 'image/jpeg')

      batch = Administrate::MCP::UploadBatch.sole
      expect(batch).to have_attributes(admin:)
      expect(batch.expires_at).to be_within(5.seconds).of(1.hour.from_now)
      expect(batch.file(uploads['logo.png'][:upload_id])).to include(
        'filename' => 'logo.png', 'content_type' => 'image/png', 'size' => 1024,
        'key' => "#{uploads['logo.png'][:upload_id]}.png"
      )
    end

    it 'signs the URL for 15 minutes by default' do
      url = prepare['logo.png'][:url]

      expect(Rack::Utils.parse_query(URI(url).query)).to include('X-Amz-Expires' => '900')
    end

    it 'refuses a file type outside the allowed ones and records nothing' do
      expect { prepare('notes.pdf' => 10, 'logo.png' => 10) }
        .to raise_error(Administrate::MCP::InvalidArgumentError, /notes\.pdf is not an allowed file type/)
      expect(Administrate::MCP::UploadBatch.count).to eq(0)
    end

    it 'refuses a declared size above the maximum' do
      expect { prepare('logo.png' => (10 * 1024 * 1024) + 1) }
        .to raise_error(Administrate::MCP::InvalidArgumentError, /logo\.png size must be between 1 and 10485760 bytes/)
    end

    it 'honours the configured types and maximum size' do
      Administrate::MCP.config.uploads.allowed_content_types = { '.pdf' => 'application/pdf' }
      Administrate::MCP.config.uploads.max_size = 100

      expect(prepare('notes.pdf' => 100)['notes.pdf'][:headers]).to eq('Content-Type' => 'application/pdf')
      expect { prepare('notes.pdf' => 101) }.to raise_error(Administrate::MCP::InvalidArgumentError)
    end

    it 'refuses an empty list' do
      expect { prepare({}) }.to raise_error(Administrate::MCP::InvalidArgumentError, /at least one file/)
    end

    it 'explains a storage that cannot presign' do
      Shrine.storages[:cache] = Shrine::Storage::Memory.new

      expect { prepare }.to raise_error(
        Administrate::MCP::ConfigurationError,
        /Shrine storage :cache \(Shrine::Storage::Memory\) cannot presign uploads/
      )
    end
  end

  describe '.resolve' do
    let(:upload_id) { prepare['logo.png'][:upload_id] }

    def resolve(as: admin)
      described_class.resolve(admin: as, upload_id:)
    end

    it 'returns the cached file data with its real metadata' do
      put_object(entry_for(upload_id)['key'], png)

      expect(resolve).to eq(
        'id' => "#{upload_id}.png",
        'storage' => 'cache',
        'metadata' => { 'filename' => 'logo.png', 'size' => png.bytesize, 'mime_type' => 'image/png' }
      )
    end

    it 'refuses content whose real type is not allowed, whatever the extension' do
      put_object(entry_for(upload_id)['key'], '%PDF-1.4 not an image')

      expect { resolve }.to raise_error(
        Administrate::MCP::InvalidArgumentError,
        "Upload #{upload_id} is application/pdf, expected one of image/png, image/jpeg, image/webp"
      )
    end

    it 'refuses a real size above the maximum, since the presigned PUT does not limit it' do
      put_object(entry_for(upload_id)['key'], png)
      Administrate::MCP.config.uploads.max_size = png.bytesize - 1

      expect { resolve }.to raise_error(
        Administrate::MCP::InvalidArgumentError,
        "Upload #{upload_id} is #{png.bytesize} bytes, the maximum is #{png.bytesize - 1}"
      )
    end

    it 'reports a file that was never uploaded' do
      expect { resolve }.to raise_error(Administrate::MCP::InvalidArgumentError, /has not been uploaded yet/)
    end

    it 'refuses an expired batch' do
      put_object(entry_for(upload_id)['key'], png)
      Administrate::MCP::UploadBatch.sole.update!(expires_at: 1.minute.ago)

      expect { resolve }.to raise_error(Administrate::MCP::InvalidArgumentError, /Upload #{upload_id} expired at/)
    end

    it "answers another admin's upload as not found" do
      put_object(entry_for(upload_id)['key'], png)

      expect { resolve(as: create(:admin, :full_access)) }
        .to raise_error(Administrate::MCP::InvalidArgumentError, "Upload #{upload_id} not found")
    end

    it 'answers an unknown upload_id as not found' do
      expect { described_class.resolve(admin:, upload_id: SecureRandom.uuid) }
        .to raise_error(Administrate::MCP::InvalidArgumentError, /not found/)
    end
  end
end
