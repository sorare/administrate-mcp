# frozen_string_literal: true

require 'administrate/mcp/errors'
require 'administrate/mcp/version'
require 'administrate/mcp/authorization/base'
require 'administrate/mcp/authorization/permissive'
require 'administrate/mcp/authorization/pundit'

module Administrate
  module MCP
    # Everything a host application supplies to the engine. Every entry has a default that works
    # without the host, except the origins and `current_admin`, which the OAuth flow needs.
    class Configuration
      SKIPPED_FIELD_CLASSES = ['Administrate::Field::Password'].freeze

      HAS_MANY_FIELD_CLASSES = ['Administrate::Field::HasMany'].freeze

      FIELD_SERIALIZERS = {
        'Administrate::Field::HasMany' => :has_many,
        'Administrate::Field::Polymorphic' => :polymorphic,
        'Administrate::Field::BelongsTo' => :belongs_to,
        'Administrate::Field::HasOne' => :belongs_to,
        'Administrate::Field::DateTime' => :datetime,
        'Administrate::Field::Date' => :datetime,
        'Administrate::Field::Time' => :datetime,
        'Administrate::Field::Enum' => :enum,
        'Administrate::Field::Select' => :enum,
        'Administrate::Field::Shrine' => :attachment,
        'Administrate::Field::String' => :scalar,
        'Administrate::Field::Text' => :scalar,
        'Administrate::Field::Email' => :scalar,
        'Administrate::Field::Url' => :scalar,
        'Administrate::Field::Number' => :scalar,
        'Administrate::Field::Boolean' => :scalar
      }.freeze

      attr_accessor :server_name,
                    :server_version,
                    :issuer,
                    :admin_origin,
                    :current_admin,
                    :sign_in,
                    :admin_class_name,
                    :authorization,
                    :default_required_roles,
                    :tool_paths,
                    :dashboard_paths,
                    :instrument,
                    :on_tool_call,
                    :on_feedback,
                    :allow_localhost_redirects,
                    :default_client_name,
                    :sidekiq_stats_provider,
                    :admin_route_namespace,
                    :admin_url_options,
                    :skipped_field_classes,
                    :has_many_field_classes,
                    :field_serializers

      attr_reader :api_key_token_prefix

      def initialize
        assign_identity
        assign_hooks
        assign_fields
      end

      def assign_identity
        @server_name = 'administrate_mcp'
        @server_version = VERSION
        @issuer = nil
        @admin_origin = nil
        @current_admin = ->(_controller) {}
        @sign_in = nil
        @admin_class_name = 'Administrator'
        @authorization = default_authorization
        @default_required_roles = []
        @tool_paths = []
        @dashboard_paths = nil
      end

      def assign_hooks
        @instrument = ->(tool_name:, admin:, &block) { block.call } # rubocop:disable Lint/UnusedBlockArgument
        @on_tool_call = ->(tool_name:, admin:, arguments:, scopes:) {}
        @on_feedback = ->(feedback) {}
        @allow_localhost_redirects = true
        @api_key_token_prefix = 'amcp_'
        @default_client_name = 'MCP Client'
        @sidekiq_stats_provider = nil
      end

      def assign_fields
        @admin_route_namespace = :admin
        @admin_url_options = {}
        @skipped_field_classes = SKIPPED_FIELD_CLASSES.dup
        @has_many_field_classes = HAS_MANY_FIELD_CLASSES.dup
        @field_serializers = FIELD_SERIALIZERS.dup
      end

      # The prefix is what tells a bearer token apart from an OAuth token, so a blank one would send
      # every OAuth token down the API key path.
      def api_key_token_prefix=(prefix)
        raise ArgumentError, 'api_key_token_prefix cannot be blank' if prefix.blank?

        @api_key_token_prefix = prefix.to_s
      end

      def register_field(class_name, as: nil, &serializer)
        @field_serializers = @field_serializers.merge(class_name.to_s => as || serializer)
        self
      end

      def skip_field(*class_names)
        @skipped_field_classes |= class_names.map(&:to_s)
        self
      end

      def register_has_many_field(*class_names)
        @has_many_field_classes |= class_names.map(&:to_s)
        self
      end

      def admin_class
        @admin_class_name.to_s.constantize
      end

      def issuer_for(request = nil)
        resolve_origin(@issuer, request)
      end

      def admin_origin_for(request = nil)
        resolve_origin(@admin_origin, request)
      end

      def dashboard_directories
        Array(@dashboard_paths.presence || Rails.root.join('app/dashboards')).map(&:to_s)
      end

      private

      def resolve_origin(origin, request)
        return origin.arity.zero? ? origin.call : origin.call(request) if origin.respond_to?(:call)

        origin.to_s
      end

      def default_authorization
        defined?(::Pundit) ? Authorization::Pundit.new : Authorization::Permissive.new
      end
    end
  end
end
