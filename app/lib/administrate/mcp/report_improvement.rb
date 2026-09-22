# frozen_string_literal: true

module Administrate
  module MCP
    # Validates an MCP improvement suggestion and hands a plain report to the host's `on_feedback`
    # hook. Persisting the report to the `Feedback` table is opt-in through `config.persist_feedback`;
    # when that is off, nothing here touches `Feedback` or `ApiKey`, so a host that never turns it on
    # need not carry the table at all.
    class ReportImprovement
      Result = Struct.new(:success?, :report, :errors, keyword_init: true)

      def self.call(...)
        new(...).call
      end

      def initialize(admin:, category:, suggestion:, resource_name: nil)
        @admin = admin
        @category = category
        @suggestion = suggestion
        @resource_name = resource_name
      end

      def call
        errors = validation_errors
        return Result.new(success?: false, report: nil, errors:) if errors.any?

        report = build_report
        notify(report)
        Result.new(success?: true, report:, errors: [])
      end

      private

      attr_reader :admin, :category, :suggestion, :resource_name

      def validation_errors
        errors = []
        unless FeedbackCategories::CATEGORIES.key?(category.to_s)
          errors << "category must be one of: #{FeedbackCategories::CATEGORIES.keys.join(', ')}"
        end
        errors << "suggestion can't be blank" if suggestion.blank?
        errors
      end

      def build_report
        record = create_feedback if persist_feedback?
        FeedbackReport.new(admin:, category:, suggestion:, resource_name:, record:, api_key: record&.api_key)
      end

      def persist_feedback?
        Administrate::MCP.config.persist_feedback
      end

      def create_feedback
        Feedback.create!(admin:, api_key: latest_api_key, category:, resource_name:, suggestion:)
      end

      def latest_api_key
        ApiKey.active.where(admin:).order(last_used_at: :desc).first
      end

      def notify(report)
        Administrate::MCP.config.on_feedback.call(report)
      rescue StandardError => e
        Administrate::MCP.config.on_error.call(e)
      end
    end
  end
end
