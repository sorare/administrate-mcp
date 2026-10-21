# frozen_string_literal: true

RSpec.describe Administrate::MCP::Actions do
  let(:admin) { create(:admin, :full_access) }
  let(:gadget) { create(:gadget) }

  after { described_class.reset! }

  describe '.build_spec' do
    it 'defaults the predicate to the action name and the scope to write' do
      spec = described_class.build_spec(:approve, description: 'Approve it') { nil }

      expect(spec).to include(name: :approve, on: :member, predicate: :approve?, scope: :write, destructive: true)
    end

    it 'defaults the predicate of a collection action to the action name too' do
      spec = described_class.build_spec(:import, on: :collection, description: 'Import some') { nil }

      expect(spec).to include(on: :collection, predicate: :import?)
    end

    it 'keeps an explicit predicate on a collection action' do
      spec = described_class.build_spec(:import, on: :collection, description: 'Import', pundit: :import?) { nil }

      expect(spec[:predicate]).to eq(:import?)
    end

    it 'refuses an unknown target' do
      expect { described_class.build_spec(:import, on: :everything, description: 'Import') { nil } }
        .to raise_error(ArgumentError, /on: must be :member or :collection/)
    end

    it 'accepts the pundit: alias for the predicate' do
      spec = described_class.build_spec(:approve, description: 'Approve it', pundit: :moderate?) { nil }

      expect(spec[:predicate]).to eq(:moderate?)
    end

    it 'reads a param spec declared with String keys throughout' do
      spec = described_class.build_spec(
        :comment, description: 'Comment',
                  params: { 'note' => { 'type' => 'string', 'description' => 'A note', 'required' => false } }
      ) { nil }

      expect(spec[:params]).to eq(note: { type: 'string', description: 'A note' })
      expect(spec[:required]).to eq([])
    end

    it 'keys params by symbol whichever way they were declared' do
      spec = described_class.build_spec(:comment, description: 'Comment', params: { 'body' => 'The body' }) { nil }

      expect(spec[:params].keys).to eq([:body])
      expect(spec[:required]).to eq([:body])
    end

    it 'expands a String param into a string schema and marks it required' do
      spec = described_class.build_spec(:comment, description: 'Comment', params: { body: 'The body' }) { nil }

      expect(spec[:params]).to eq(body: { type: 'string', description: 'The body' })
      expect(spec[:required]).to eq([:body])
    end

    it 'leaves an explicitly optional param out of required' do
      spec =
        described_class.build_spec(
          :comment,
          description: 'Comment',
          params: { body: { type: 'string', required: false } }
        ) { nil }

      expect(spec[:required]).to eq([])
      expect(spec[:params][:body]).not_to have_key(:required)
    end

    it 'demands an invocation block' do
      expect { described_class.build_spec(:comment, description: 'Comment') }.to raise_error(ArgumentError)
    end

    %w[admin id].each do |reserved|
      it "refuses a param named #{reserved}" do
        expect { described_class.build_spec(:comment, description: 'Comment', params: { reserved => 'Taken' }) { nil } }
          .to raise_error(ArgumentError, /reserved param name\(s\): #{reserved}/)
      end
    end

    it 'accepts params named like the block keywords they are nested under' do
      spec = described_class.build_spec(:comment, description: 'Comment', params: { record: 'R', params: 'P' }) { nil }

      expect(spec[:params].keys).to eq(%i[record params])
    end
  end

  describe '.definitions' do
    it 'picks up the dashboard declaration' do
      definition = described_class.definitions.find { |d| d.name == :relabel }

      expect(definition.model_class).to eq(Gadget)
      expect(definition.predicate).to eq(:relabel?)
    end
  end

  describe '.tools_for' do
    it 'hides the tool from a caller without the write scope' do
      names = described_class.tools_for({ admin:, scopes: [] }).map(&:name_value)

      expect(names).to be_empty
    end

    it 'exposes the tool once the write scope is granted' do
      names = described_class.tools_for({ admin:, scopes: ['write'] }).map(&:name_value)

      expect(names).to contain_exactly('gadget_relabel', 'widget_create_draft')
    end

    context 'with an authorization adapter that refuses the predicate' do
      before do
        Administrate::MCP.config.authorization = Class.new(Administrate::MCP::Authorization::Base) do
          def authorized?(_admin, _record_or_class, _action) = false
        end.new
      end

      it 'hides the tool' do
        expect(described_class.tools_for({ admin:, scopes: ['write'] })).to be_empty
      end
    end

    context 'with an authorization adapter that refuses create? on the model class' do
      let(:checks) { [] }

      before do
        seen = checks
        Administrate::MCP.config.authorization = Class.new(Administrate::MCP::Authorization::Base) do
          define_method(:authorized?) do |_admin, record_or_class, action|
            seen << [record_or_class, action]
            action != :create?
          end
        end.new
      end

      it 'hides the collection tool and keeps the member tool' do
        names = described_class.tools_for({ admin:, scopes: ['write'] }).map(&:name_value)

        expect(names).to eq(['gadget_relabel'])
        expect(checks).to include([an_instance_of(Widget), :create?])
      end
    end
  end

  describe 'the generated tool' do
    def build_member_tool(&block)
      spec = described_class.build_spec(:fix, description: 'Fix a gadget', &block)
      described_class::ToolFactory.build(described_class::Definition.new(model_class: Gadget, **spec))
    end

    subject(:tool) { described_class.all_tools.find { |t| t.name_value == 'gadget_relabel' } }

    it 'requires an id plus the declared params' do
      expect(tool.input_schema.to_h[:required]).to eq(%w[id label])
    end

    it 'refuses undeclared arguments' do
      expect(tool.input_schema.to_h[:additionalProperties]).to be(false)
    end

    it 'runs the declared block against the loaded record' do
      result = tool.call(id: gadget.id, label: 'Renamed', server_context: { admin:, scopes: ['write'] })

      expect(JSON.parse(result.content.first[:text])).to include('status' => 'ok', 'action' => 'relabel')
      expect(gadget.reload.label).to eq('Renamed')
    end

    it 'echoes the id the caller passed, slug or primary key' do
      result = tool.call(id: gadget.id, label: 'Renamed', server_context: { admin:, scopes: ['write'] })

      expect(JSON.parse(result.content.first[:text])).to include('id' => gadget.id)
    end

    it 'reports a member action that returns the record it destroyed as a success' do
      destroy = build_member_tool { |record:, **| record.destroy }
      result = destroy.call(id: gadget.id, server_context: { admin:, scopes: ['write'] })

      expect(JSON.parse(result.content.first[:text])).to include('status' => 'ok', 'id' => gadget.id)
      expect(Gadget.where(id: gadget.id)).not_to exist
    end

    it 'reports a block that returns false as an error with the record validation messages' do
      relabel = build_member_tool do |record:, **|
        record.errors.add(:label, :blank)
        false
      end
      result = relabel.call(id: gadget.id, server_context: { admin:, scopes: ['write'] })

      expect(result.error?).to be(true)
      expect(result.content.first[:text]).to eq("Label can't be blank")
    end

    it 'reports a destroy aborted by a callback as a failure of the action' do
      relabel = build_member_tool { |record:, **| record.destroy }
      allow(Gadget).to receive(:find_by).with(id: gadget.id).and_return(gadget)
      allow(gadget).to receive(:destroy).and_return(false)
      result = relabel.call(id: gadget.id, server_context: { admin:, scopes: ['write'] })

      expect(result.content.first[:text]).to eq('fix failed')
      expect(Gadget.where(id: gadget.id)).to exist
    end

    it 'reports a record returned with errors as an error' do
      relabel = build_member_tool { |record:, **| record.tap { record.errors.add(:label, :blank) } }
      result = relabel.call(id: gadget.id, server_context: { admin:, scopes: ['write'] })

      expect(result.content.first[:text]).to eq("Label can't be blank")
    end

    it 'closes the schema to undeclared arguments' do
      expect(tool.input_schema.to_h).to include(additionalProperties: false)
    end

    it 'reports an unknown record as an authorization error' do
      ctx = { admin:, scopes: ['write'] }
      result = tool.call(id: SecureRandom.uuid, label: 'Renamed', server_context: ctx)

      expect(result.content.first[:text]).to include('not found')
      expect(ctx[:authorization_errors]).not_to be_empty
    end
  end

  describe 'a generated collection tool' do
    subject(:tool) { described_class.all_tools.find { |t| t.name_value == 'widget_create_draft' } }

    let(:ctx) { { admin:, scopes: ['write'] } }

    def build_tool(**options, &block)
      spec = described_class.build_spec(:import, on: :collection, description: 'Import a widget', **options, &block)
      described_class::ToolFactory.build(described_class::Definition.new(model_class: Widget, **spec))
    end

    it 'takes the declared params and no id' do
      schema = tool.input_schema.to_h

      expect(schema[:properties].keys).to eq([:name])
      expect(schema[:required]).to eq(%w[name])
    end

    it 'keeps the resource_name tool name' do
      expect(tool.name_value).to eq('widget_create_draft')
    end

    it 'runs the block with the admin and params and returns the created record id' do
      result = tool.call(name: 'Fresh', server_context: ctx)

      widget = Widget.find_by!(name: 'Fresh')
      expect(widget).to have_attributes(admin:, status: 'draft')
      expect(JSON.parse(result.content.first[:text]))
        .to eq('status' => 'ok', 'model' => 'widget', 'action' => 'create_draft', 'id' => widget.id)
    end

    it 'answers without an id when the block returns something other than a record' do
      result = build_tool { |**| true }.call(server_context: ctx)

      expect(JSON.parse(result.content.first[:text])).to eq('status' => 'ok', 'model' => 'widget', 'action' => 'import')
    end

    it 'reports a record that was not saved as an error with its validation messages' do
      invalid = Widget.new.tap { |widget| widget.errors.add(:name, :blank) }
      result = build_tool { |**| invalid }.call(server_context: ctx)

      expect(result.error?).to be(true)
      expect(result.content.first[:text]).to eq("Name can't be blank")
    end

    it 'reports a record returned unsaved and without errors as a failure of the action' do
      result = build_tool { |**| Widget.new(name: 'Never saved') }.call(server_context: ctx)

      expect(result.content.first[:text]).to eq('import failed')
    end

    it 'closes the schema to undeclared arguments' do
      expect(tool.input_schema.to_h).to include(additionalProperties: false)
    end

    it 'has undeclared arguments refused by the server before the action runs' do
      server = Administrate::MCP::ServerBuilder.build(server_context: ctx.dup)
      response = server.handle(
        { jsonrpc: '2.0', id: 1, method: 'tools/call',
          params: { name: 'widget_create_draft', arguments: { name: 'Fresh', status: 'published' } } }
      )

      expect(response.dig(:result, :isError)).to be(true)
      expect(response.dig(:result, :content, 0, :text)).to include('Invalid arguments')
      expect(Widget.unscoped.where(name: 'Fresh')).not_to exist
    end

    it 'passes a param declared with a String key to the block' do
      seen = nil
      build_tool(params: { 'reference' => 'Reference' }) { |params:, **| seen = params }
        .call(reference: 'R-1', server_context: ctx)

      expect(seen).to eq(reference: 'R-1')
    end

    it 'passes only the declared params to the block' do
      seen = nil
      build_tool(params: { name: 'Name' }) { |params:, **| seen = params }
        .call(name: 'Fresh', status: 'published', server_context: ctx)

      expect(seen).to eq(name: 'Fresh')
    end

    it 'reports a result answering success? == false as an error' do
      failure = Struct.new(:error) { def success? = false }.new('Name already taken')
      result = build_tool { |**| failure }.call(server_context: ctx)

      expect(result.error?).to be(true)
      expect(result.content.first[:text]).to eq('Name already taken')
    end

    it 'refuses the call without the write scope' do
      result = tool.call(name: 'Fresh', server_context: { admin:, scopes: [] })

      expect(result.content.first[:text]).to include('Missing required scope(s): write')
      expect(Widget.where(name: 'Fresh')).not_to exist
    end

    it 'reports the call to the audit hook' do
      seen = []
      Administrate::MCP.config.on_tool_call = ->(**args) { seen << args }

      tool.call(name: 'Fresh', server_context: ctx)

      expect(seen).to eq(
        [{ tool_name: 'widget_create_draft', admin:, arguments: { name: 'Fresh' }, scopes: ['write'] }]
      )
    end

    context 'with an authorization adapter that refuses create? on the model class' do
      before do
        Administrate::MCP.config.authorization = Class.new(Administrate::MCP::Authorization::Base) do
          def authorized?(_admin, record_or_class, action) = !(record_or_class.is_a?(Widget) && action == :create?)
        end.new
      end

      it 'refuses the call before running the block or auditing it' do
        audited = []
        Administrate::MCP.config.on_tool_call = ->(**args) { audited << args }

        result = tool.call(name: 'Fresh', server_context: ctx)

        expect(result.content.first[:text]).to eq('Not authorized to create? Widget')
        expect(ctx[:authorization_errors]).to eq(['Not authorized to create? Widget'])
        expect(audited).to be_empty
        expect(Widget.where(name: 'Fresh')).not_to exist
      end
    end

    context 'with the Pundit adapter' do
      let(:allowed) { true }

      before do
        Administrate::MCP.config.authorization = Administrate::MCP::Authorization::Pundit.new
        create_allowed = allowed
        stub_const(
          'WidgetPolicy',
          Class.new do
            define_method(:initialize) { |_admin, record| @record = record }
            define_method(:create?) { create_allowed && @record.new_record? && @record.status == 'draft' }
          end
        )
      end

      it 'publishes the tool and runs it when the policy allows create? on a new record' do
        names = described_class.tools_for(ctx).map(&:name_value)
        result = tool.call(name: 'Fresh', server_context: ctx)

        expect(names).to include('widget_create_draft')
        expect(result.error?).to be(false)
        expect(Widget.where(name: 'Fresh')).to exist
      end

      context 'when the policy refuses create?' do
        let(:allowed) { false }

        it 'hides the tool and refuses the call' do
          names = described_class.tools_for(ctx).map(&:name_value)
          result = tool.call(name: 'Fresh', server_context: ctx)

          expect(names).not_to include('widget_create_draft')
          expect(result.content.first[:text]).to eq('Not authorized to create? Widget')
          expect(Widget.where(name: 'Fresh')).not_to exist
        end
      end
    end

    context 'with a custom predicate' do
      it 'checks that predicate against a new instance of the model' do
        checks = []
        Administrate::MCP.config.authorization = Class.new(Administrate::MCP::Authorization::Base) do
          define_method(:authorized?) { |_admin, record_or_class, action| checks << [record_or_class, action] }
        end.new

        build_tool(predicate: :import?) { |**| true }.call(server_context: ctx)

        expect(checks).to contain_exactly([an_instance_of(Widget), :import?])
      end
    end
  end

  describe 'an action declared with uploads' do
    include_context 'with presignable storage'

    let(:ctx) { { admin:, scopes: ['write'] } }
    let(:create_draft) { described_class.all_tools.find { |t| t.name_value == 'widget_create_draft' } }

    def declare_member_action(uploads:, dashboard: WidgetDashboard, model: Widget, **options, &block)
      spec = described_class.build_spec(:repaint, description: 'Repaint', uploads:, **options, &block)
      uploads = Administrate::MCP::Uploads::Declarations.action_attributes(dashboard, :repaint, spec[:uploads])
      definition = described_class::Definition.new(model_class: model, **spec, uploads:)
      allow(described_class).to(receive(:definitions).and_wrap_original { |original| original.call + [definition] })
      described_class::ToolFactory.build(definition)
    end

    it 'publishes an optional upload_id param for each attachment attribute' do
      schema = create_draft.input_schema.to_h

      expect(schema[:properties]).to include(picture_upload_id: hash_including(type: 'string'))
      expect(schema[:required]).to eq(%w[name])
    end

    it 'sets the attribute from the uploaded file' do
      result = create_draft.call(name: 'Fresh', picture_upload_id: upload_png, server_context: ctx)

      expect(result.error?).to be(false)
      picture = Widget.find_by!(name: 'Fresh').picture
      expect(picture).to have_attributes(mime_type: 'image/png', size: png.bytesize, original_filename: 'logo.png')
      expect(picture.read).to eq(png)
    end

    it 'leaves the attribute out when no upload_id is given' do
      create_draft.call(name: 'Fresh', server_context: ctx)

      expect(Widget.find_by!(name: 'Fresh').picture).to be_nil
    end

    it 'accepts the same upload_id again after the action failed' do
      upload_id = upload_png
      allow(Widget).to receive(:create!).and_wrap_original do |original, **attributes|
        raise ActiveRecord::RecordInvalid if attributes[:name] == 'Taken'

        original.call(**attributes)
      end

      failed = create_draft.call(name: 'Taken', picture_upload_id: upload_id, server_context: ctx)
      retried = create_draft.call(name: 'Fresh', picture_upload_id: upload_id, server_context: ctx)

      expect(failed.error?).to be(true)
      expect(retried.error?).to be(false)
      expect(Widget.find_by!(name: 'Fresh').picture.read).to eq(png)
    end

    it "refuses another admin's upload before running the block" do
      result = create_draft.call(name: 'Fresh', picture_upload_id: upload_png(admin: create(:admin)),
                                 server_context: ctx)

      expect(result.error?).to be(true)
      expect(result.content.first[:text]).to match(/Upload .* not found/)
      expect(Widget.where(name: 'Fresh')).not_to exist
    end

    it 'hands the resolved value to a member action as params[attribute]' do
      widget = create(:widget)
      tool = declare_member_action(uploads: [:picture]) do |record:, params:, **|
        record.update!(picture: params[:picture])
      end

      tool.call(id: widget.id, picture_upload_id: upload_png(tool: 'widget_repaint'), server_context: ctx)

      expect(widget.reload.picture.read).to eq(png)
    end

    it 'refuses an upload prepared for another action' do
      widget = create(:widget)
      tool = declare_member_action(uploads: [:picture]) do |record:, params:, **|
        record.update!(picture: params[:picture])
      end

      result = tool.call(id: widget.id, picture_upload_id: upload_png, server_context: ctx)

      expect(result.content.first[:text]).to include('was prepared for widget_create_draft picture')
      expect(widget.reload.picture).to be_nil
    end

    it 'applies per-attribute content types and maximum size' do
      declare_member_action(uploads: { picture: { content_types: { '.gif' => 'image/gif' }, max_size: 100 } }) do |**|
        true
      end

      expect { prepare_upload({ 'logo.png' => 10 }, tool: 'widget_repaint') }
        .to raise_error(Administrate::MCP::InvalidArgumentError, /logo\.png is not an allowed file type \(\.gif\)/)
      expect { prepare_upload({ 'logo.gif' => 101 }, tool: 'widget_repaint') }
        .to raise_error(Administrate::MCP::InvalidArgumentError, /between 1 and 100 bytes/)
      expect(prepare_upload({ 'logo.gif' => 100 }, tool: 'widget_repaint')['logo.gif'][:fields])
        .to include('Content-Type' => 'image/gif')
    end

    it 'refuses to prepare uploads for an action whose scope the caller was not granted' do
      declare_member_action(uploads: [:picture], scope: :billing) { |**| true }

      expect { prepare_upload(tool: 'widget_repaint') }
        .to raise_error(Administrate::MCP::InvalidArgumentError, /No action widget_repaint .* available to you/)
      expect(prepare_upload(tool: 'widget_repaint', scopes: %w[write billing])).to include('logo.png')
    end

    it 'uses the granted scopes even when the client sends its own' do
      declare_member_action(uploads: [:picture], scope: :billing) { |**| true }
      tool = Administrate::MCP::Tools::UploadsPrepare

      result = tool.call(tool: 'widget_repaint', attribute: 'picture', files: { 'logo.png': 10 }, scopes: ['billing'],
                         server_context: { admin:, scopes: ['write'] })

      expect(result.content.first[:text]).to include('No action widget_repaint')
      expect(Administrate::MCP::UploadBatch.count).to eq(0)
    end

    {
      'a list of content types' => { content_types: %w[image/png] },
      'an extension without its dot' => { content_types: { 'png' => 'image/png' } },
      'an unknown rule' => { max_bytes: 1024 },
      'a non-positive max_size' => { max_size: 0 }
    }.each do |label, rules|
      it "refuses #{label} when the dashboard loads" do
        expect { described_class.build_spec(:repaint, description: 'Repaint', uploads: { picture: rules }) { nil } }
          .to raise_error(ArgumentError, /repaint: uploads: picture/)
      end
    end

    it 'refuses an uploads: entry that is not an attachment attribute' do
      expect { declare_member_action(uploads: [:name]) { |**| true } }
        .to raise_error(ArgumentError, /uploads: names name, which are not attachment attributes/)
    end

    it 'refuses uploads: true on a dashboard without an attachment attribute' do
      expect { declare_member_action(uploads: true, dashboard: GadgetDashboard, model: Gadget) { |**| true } }
        .to raise_error(ArgumentError, /uploads: true, but the dashboard has no attachment attribute/)
    end

    it 'publishes no upload param while uploads are disabled' do
      Administrate::MCP.config.uploads.enabled = false
      described_class.reset!

      expect(create_draft.input_schema.to_h[:properties].keys).to eq([:name])
    end
  end
end
