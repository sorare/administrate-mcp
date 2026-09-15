# frozen_string_literal: true

class SessionsController < ActionController::Base
  def new
    render plain: 'sign in'
  end
end
