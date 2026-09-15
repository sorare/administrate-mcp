# frozen_string_literal: true

module Administrate
  module MCP
    # OAuth 2.1 endpoints for MCP authentication.
    class OAuthController < ActionController::Base
      skip_forgery_protection only: %i[resource_metadata server_metadata register token]
      before_action :authenticate_admin!, only: %i[authorize approve]

      def resource_metadata
        render json: {
          resource: "#{mcp_origin}/",
          authorization_servers: [mcp_origin],
          bearer_methods_supported: ['header']
        }
      end

      def server_metadata
        render json: {
          issuer: mcp_origin,
          authorization_endpoint: "#{admin_origin}#{Routes::AUTHORIZE_PATH}",
          token_endpoint: "#{mcp_origin}/oauth/token",
          registration_endpoint: "#{mcp_origin}/oauth/register",
          response_types_supported: ['code'],
          grant_types_supported: %w[authorization_code refresh_token],
          code_challenge_methods_supported: ['S256'],
          token_endpoint_auth_methods_supported: ['none']
        }
      end

      def register
        application = build_application
        return render(json: registration_error(application), status: :bad_request) unless application.save

        render json: {
                 client_id: application.client_id,
                 client_name: application.name,
                 redirect_uris: application.redirect_uris,
                 grant_types: application.grant_types
               },
               status: :created
      end

      def authorize
        @application = OAuthApplication.find_by(client_id: params[:client_id])
        error =
          oauth_service.validate_authorize_params(
            application: @application,
            redirect_uri: params[:redirect_uri],
            code_challenge_method: params[:code_challenge_method],
            code_challenge: params[:code_challenge]
          )
        return render plain: error, status: :bad_request if error

        assign_consent_details
        render 'administrate/mcp/o_auth/authorize', layout: false
      end

      def approve
        application = find_application!
        return unless application

        redirect_uri = validated_redirect_uri!(application)
        return unless redirect_uri

        if params[:deny].present?
          return redirect_to "#{redirect_uri}?error=access_denied&state=#{encoded_state}", allow_other_host: true
        end

        grant = create_access_grant(application, redirect_uri)
        redirect_to "#{redirect_uri}?code=#{ERB::Util.url_encode(grant.token)}&state=#{encoded_state}",
                    allow_other_host: true
      end

      def token
        case params[:grant_type]
        when 'authorization_code'
          handle_authorization_code
        when 'refresh_token'
          handle_refresh_token
        else
          render json: { error: 'unsupported_grant_type' }, status: :bad_request
        end
      end

      private

      def build_application
        OAuthApplication.new(
          client_id: OAuthApplication.generate_client_id,
          name: register_params[:client_name] || Administrate::MCP.config.default_client_name,
          redirect_uris: register_params[:redirect_uris] || []
        )
      end

      def registration_error(application)
        { error: 'invalid_client_metadata', error_description: application.errors.full_messages.join(', ') }
      end

      def handle_authorization_code
        result =
          oauth_service.exchange_authorization_code(
            code: params[:code],
            code_verifier: params[:code_verifier],
            redirect_uri: params[:redirect_uri]
          )
        render_token_result(result)
      end

      def handle_refresh_token
        result = oauth_service.exchange_refresh_token(refresh_token: params[:refresh_token])
        render_token_result(result)
      end

      def render_token_result(result)
        if result.success?
          render json: result.data
        else
          body = { error: result.error }
          body[:error_description] = result.error_description if result.error_description
          render json: body, status: :bad_request
        end
      end

      def create_access_grant(application, redirect_uri)
        OAuthAccessGrant.create!(
          admin: current_admin,
          application:,
          token: OAuthAccessGrant.generate_token,
          expires_in: OAuthAccessGrant::DEFAULT_EXPIRES_IN,
          redirect_uri:,
          code_challenge: params[:code_challenge],
          code_challenge_method: params[:code_challenge_method].presence || 'S256',
          scopes: params[:scope].to_s
        )
      end

      def find_application!
        application = OAuthApplication.find_by(client_id: params[:client_id])
        render(plain: 'Unknown client_id', status: :bad_request) unless application
        application
      end

      def validated_redirect_uri!(application)
        uri = params[:redirect_uri]
        render(plain: 'Invalid redirect_uri', status: :bad_request) unless oauth_service.valid_redirect_uri?(
          application,
          uri
        )
        uri
      end

      def encoded_state
        ERB::Util.url_encode(params[:state].to_s)
      end

      def assign_consent_details
        @redirect_uri = params[:redirect_uri]
        @scopes = params[:scope].to_s.split
        @redirect_host = URI.parse(@redirect_uri.to_s).host
      rescue URI::InvalidURIError
        @redirect_host = nil
      end

      def register_params
        params.permit(:client_name, redirect_uris: [])
      end

      def oauth_service
        @oauth_service ||= OAuthService.new
      end

      def authenticate_admin!
        return if current_admin

        sign_in = Administrate::MCP.config.sign_in
        return sign_in.call(self) if sign_in

        render plain: 'Authentication required', status: :unauthorized
      end

      def current_admin
        return @current_admin if defined?(@current_admin)

        @current_admin = Administrate::MCP.config.current_admin.call(self)
      end

      def mcp_origin
        Administrate::MCP.config.issuer_for(request)
      end

      def admin_origin
        Administrate::MCP.config.admin_origin_for(request)
      end
    end
  end
end
