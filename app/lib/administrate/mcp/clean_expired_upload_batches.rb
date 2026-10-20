# frozen_string_literal: true

module Administrate
  module MCP
    # Removes upload batches that expired before the given cutoff, one batch at a time. The caller
    # decides whether to run the next batch: `call` reports whether the batch was full. The
    # uploaded objects are left to the bucket's own lifecycle rule.
    class CleanExpiredUploadBatches
      BATCH_SIZE = 10_000

      Result = Struct.new(:deleted_count, :more?, keyword_init: true)

      def self.call(...)
        new(...).call
      end

      def initialize(till: Time.current)
        @till = till
      end

      def call
        deleted_count = UploadBatch.expired(@till).limit(BATCH_SIZE).delete_all
        Result.new(deleted_count:, more?: deleted_count == BATCH_SIZE)
      end
    end
  end
end
