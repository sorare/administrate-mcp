# frozen_string_literal: true

module Administrate
  module MCP
    # Recognises loopback redirect targets (RFC 8252). Subdomains of `.localhost` are used by
    # parallel dev checkouts and are safe. Matches on the parsed host, never a string prefix —
    # `localhost.attacker.com` is a normal, attacker-controlled DNS name and is rejected.
    module LoopbackUri
      HOSTS = %w[localhost 127.0.0.1 ::1].freeze

      def self.localhost?(host)
        return false if host.blank?

        HOSTS.include?(host) || host.end_with?('.localhost')
      end
    end
  end
end
