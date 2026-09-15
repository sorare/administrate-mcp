# frozen_string_literal: true

Rails.application.routes.draw do
  constraints ->(request) { request.subdomain == 'admin-mcp' } do
    Administrate::MCP::Routes.draw_mcp_origin(self)
  end

  constraints ->(request) { request.subdomain == 'admin' } do
    Administrate::MCP::Routes.draw_admin_origin(self)
    get '/admins/sign_in', to: 'sessions#new', as: :new_admin_session
  end

  namespace :admin do
    resources :widgets, only: %i[index show]
    resources :gadgets, only: %i[index show]
    resources :admins, only: %i[index show]
  end
end
