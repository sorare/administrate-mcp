# frozen_string_literal: true

module Administrate
  module MCP
    # Plain report of an MCP improvement suggestion, handed to `config.on_feedback` whether or not
    # `config.persist_feedback` is on. `record` and `api_key` are only set when it is, so a host that
    # wants the persisted row can reach it; the report itself never needs the `Feedback` table to
    # exist.
    FeedbackReport = Struct.new(:admin, :category, :suggestion, :resource_name, :api_key, :record, keyword_init: true)
  end
end
