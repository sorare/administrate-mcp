# frozen_string_literal: true

module Console
  # A host wiring the engine's feedback console with nothing of its own.
  class AdministrateMcpFeedbacksController < Console::ApplicationController
    include Administrate::MCP::FeedbacksAdmin
  end
end
