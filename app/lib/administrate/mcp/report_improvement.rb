# frozen_string_literal: true

module Administrate
  module MCP
    # Persists an MCP improvement suggestion and hands it to the host's `on_feedback` hook.
    class ReportImprovement
      Result = Struct.new(:success?, :feedback, :errors, keyword_init: true)

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
        return Result.new(success?: false, feedback: nil, errors:) if errors.any?

        feedback = create_feedback
        notify(feedback)
        Result.new(success?: true, feedback:, errors: [])
      end

      private

      attr_reader :admin, :category, :suggestion, :resource_name

      def validation_errors
        errors = []
        unless Feedback.categories.key?(category.to_s)
          errors << "category must be one of: #{Feedback.categories.keys.join(', ')}"
        end
        errors << "suggestion can't be blank" if suggestion.blank?
        errors
      end

      def create_feedback
        Feedback.create!(admin:, api_key: latest_api_key, category:, resource_name:, suggestion:)
      end

      def latest_api_key
        ApiKey.active.where(admin:).order(last_used_at: :desc).first
      end

      # The feedback is already persisted; a broken notifier must not take the report down with it.
      def notify(feedback)
        Administrate::MCP.config.on_feedback.call(feedback)
      rescue StandardError => e
        Administrate::MCP.config.on_error.call(e)
      end
    end
  end
end
