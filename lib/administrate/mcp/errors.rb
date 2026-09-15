# frozen_string_literal: true

module Administrate
  module MCP
    class Error < StandardError
    end

    # Raised when the caller may not perform the requested action on the resource.
    class UnauthorizedError < Error
    end

    # Raised when the caller passes an argument the resource cannot honour. Surfaced verbatim so the
    # caller can correct the call, rather than as an "Internal error".
    class InvalidArgumentError < Error
    end
  end
end
