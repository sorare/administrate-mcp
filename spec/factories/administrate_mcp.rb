# frozen_string_literal: true

FactoryBot.define do
  factory :admin do
    sequence(:email) { |n| "admin#{n}@example.com" }
    role { 'viewer' }

    trait :full_access do
      role { 'full_access' }
    end
  end

  factory :widget do
    admin
    sequence(:name) { |n| "Widget #{n}" }
    sequence(:slug) { |n| "widget-#{n}" }
    status { :draft }
    price { 100 }
  end

  factory :gadget do
    widget
    sequence(:label) { |n| "Gadget #{n}" }
  end

  factory :administrate_mcp_api_key, class: 'Administrate::MCP::ApiKey' do
    admin
    token_digest { Digest::SHA256.hexdigest("amcp_#{SecureRandom.hex(20)}") }
    token_prefix { 'amcp_abcdef12' }
    name { 'Test Key' }
  end

  factory :administrate_mcp_feedback, class: 'Administrate::MCP::Feedback' do
    admin
    category { :description }
    suggestion { 'The description is misleading' }
  end

  factory :administrate_mcp_oauth_application, class: 'Administrate::MCP::OAuthApplication' do
    client_id { SecureRandom.hex(16) }
    name { 'Test OAuth App' }
    redirect_uris { ['http://localhost:3000/callback'] }
  end

  factory :administrate_mcp_oauth_access_grant, class: 'Administrate::MCP::OAuthAccessGrant' do
    admin
    application factory: :administrate_mcp_oauth_application
    token { SecureRandom.hex(32) }
    expires_in { Administrate::MCP::OAuthAccessGrant::DEFAULT_EXPIRES_IN }
    redirect_uri { 'http://localhost:3000/callback' }
    code_challenge { Base64.urlsafe_encode64(Digest::SHA256.digest('test_verifier'), padding: false) }
    code_challenge_method { 'S256' }
  end

  factory :administrate_mcp_oauth_access_token, class: 'Administrate::MCP::OAuthAccessToken' do
    admin
    application factory: :administrate_mcp_oauth_application
    token { SecureRandom.hex(32) }
    refresh_token { SecureRandom.hex(32) }
    expires_in { Administrate::MCP::OAuthAccessToken::DEFAULT_EXPIRES_IN }
  end
end
