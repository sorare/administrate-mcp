# frozen_string_literal: true

Administrate::MCP::Engine.routes.draw do
  get '/.well-known/oauth-protected-resource', to: 'oauth#resource_metadata'
  get '/.well-known/oauth-authorization-server', to: 'oauth#server_metadata'
  post '/oauth/register', to: 'oauth#register'
  post '/oauth/token', to: 'oauth#token'
  get '/oauth/authorize', to: 'oauth#authorize'
  post '/oauth/authorize', to: 'oauth#approve'
  match '/', to: 'json_rpc#handle', via: %i[get post delete]
end
