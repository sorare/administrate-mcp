# frozen_string_literal: true

module Administrate
  module MCP
    # Removes MCP feedbacks older than the given cutoff, one batch at a time. The caller decides
    # whether to run the next batch: `call` reports whether the batch was full.
    class CleanOldFeedbacks
      BATCH_SIZE = 10_000

      Result = Struct.new(:deleted_count, :more?, keyword_init: true)

      def self.call(...)
        new(...).call
      end

      def initialize(till: 2.months.ago)
        @till = till
      end

      def call
        deleted_count = Feedback.where(created_at: ...@till).limit(BATCH_SIZE).delete_all
        Result.new(deleted_count:, more?: deleted_count == BATCH_SIZE)
      end
    end
  end
end
