# frozen_string_literal: true

module Administrate
  module MCP
    # An interactive view an MCP Apps host (SEP-1865) renders for a tool's result, served as a
    # `ui://` HTML resource. A subclass names its script and, optionally, its stylesheet; the
    # engine wraps them in a document with the shared runtime (`window.AdministrateMCP`), which
    # speaks the host's postMessage protocol. A tool opts in with `tool_view`, an `mcp_action`
    # with `view:`, and the server publishes nothing until the host sets `config.tool_views`.
    class ToolView
      RUNTIME_DIR = File.expand_path('../../../../lib/administrate/mcp/tool_views', __dir__)

      CSP_KEYS = {
        connect_domains: :connectDomains,
        resource_domains: :resourceDomains,
        frame_domains: :frameDomains,
        base_uri_domains: :baseUriDomains
      }.freeze

      class << self
        def view_name(value = nil)
          @view_name = value.to_s if value
          @view_name || name.demodulize.underscore.delete_suffix('_view')
        end

        def title(value = nil)
          @title = value if value
          @title || view_name.humanize
        end

        def description(value = nil)
          @description = value if value
          @description
        end

        def script(path = nil)
          @script = path.to_s if path
          @script
        end

        def stylesheet(path = nil)
          @stylesheet = path.to_s if path
          @stylesheet
        end

        def uri
          "#{::MCP::Apps::URI_SCHEME}#{Administrate::MCP.config.server_name.to_s.dasherize}/#{view_name}"
        end

        def resource
          view = self
          ::MCP::Resource.define(
            uri:,
            name: view_name,
            title:,
            description:,
            mime_type: ::MCP::Apps::RESOURCE_MIME_TYPE
          ) { |server_context: nil| view.contents(server_context:) }
        end

        def contents(server_context: nil) # rubocop:disable Lint/UnusedMethodArgument
          ::MCP::Resource::TextContents.new(
            uri:,
            mime_type: ::MCP::Apps::RESOURCE_MIME_TYPE,
            text: document,
            meta: { ui: resource_meta }
          )
        end

        def document
          raise ArgumentError, "#{name}: declare the view's script" if script.blank?

          <<~HTML
            <!doctype html>
            <html lang="en">
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>#{ERB::Util.html_escape(title)}</title>
            <style>#{style_text(read_runtime('runtime.css'))}#{style_text(read(stylesheet))}</style>
            </head>
            <body>
            <main id="app" aria-live="polite"><p class="am-muted">Loading…</p></main>
            <script>#{script_text(read_runtime('runtime.js'))}</script>
            <script>#{script_text(read(script))}</script>
            </body>
            </html>
          HTML
        end

        def resource_meta
          csp = Administrate::MCP.config.tool_view_csp.to_h.each_with_object({}) do |(key, domains), result|
            spec_key = CSP_KEYS[key.to_sym]
            raise ArgumentError, "Unknown tool_view_csp key: #{key}" unless spec_key

            result[spec_key] = Array(domains).map(&:to_s)
          end
          { prefersBorder: true, csp: (csp unless csp.empty?) }.compact
        end

        def runtime_path(file)
          File.join(RUNTIME_DIR, file)
        end

        private

        def read_runtime(file)
          File.read(runtime_path(file))
        end

        def read(path)
          path.present? ? File.read(path) : ''
        end

        def script_text(source)
          source.gsub(%r{</(script)}i, '<\/\1')
        end

        def style_text(source)
          source.gsub(%r{</(style)}i, '<\/\1')
        end
      end
    end
  end
end
