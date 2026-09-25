# frozen_string_literal: true

module Administrate
  module MCP
    class Error < StandardError
    end

    # Raised when the caller may not perform the requested action on the resource.
    class UnauthorizedError < Error
    end

    # Raised when the caller's role may not read one resource. It is still an authorization failure,
    # but it is returned as a tool error rather than a 403: the credentials work for the tool, only
    # this resource is out of reach, and the caller needs the message to tell the two apart.
    class ResourceForbiddenError < UnauthorizedError
    end

    # Raised when the host asked for something the configuration cannot deliver.
    class ConfigurationError < Error
    end

    # Raised when the caller passes an argument the resource cannot honour. Surfaced verbatim so the
    # caller can correct the call, rather than as an "Internal error".
    class InvalidArgumentError < Error
    end
  end
end
