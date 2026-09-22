# frozen_string_literal: true

Rails.application.routes.draw do
  constraints ->(request) { request.subdomain == 'admin-mcp' } do
    Administrate::MCP::Routes.draw_mcp_origin(self)
  end

  constraints ->(request) { request.subdomain == 'admin' } do
    Administrate::MCP::Routes.draw_admin_origin(self)
    get '/admins/sign_in', to: 'sessions#new', as: :new_admin_session
  end

  # The engine's own console, wired the way a host wires it. `Admin` is a model in this dummy, so
  # the controllers live under another namespace than the URLs the tools build.
  namespace :console do
    resources :administrate_mcp_api_keys, only: %i[index show new create destroy]
    resources :writable_administrate_mcp_api_keys, only: %i[index create]
    resources :administrate_mcp_feedbacks, only: %i[index show edit update]
  end

  namespace :admin do
    resources :widgets, only: %i[index show]
    resources :gadgets, only: %i[index show]
    resources :admins, only: %i[index show]
    resources :administrate_mcp_api_keys, only: %i[index show]
  end
end
