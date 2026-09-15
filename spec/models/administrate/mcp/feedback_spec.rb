# frozen_string_literal: true

RSpec.describe Administrate::MCP::Feedback do
  subject(:feedback) { build(:administrate_mcp_feedback) }

  describe 'validations' do
    it { is_expected.to be_valid }

    it 'requires a suggestion' do
      feedback.suggestion = nil

      expect(feedback).not_to be_valid
    end

    it 'requires a category' do
      feedback.category = nil

      expect(feedback).not_to be_valid
    end
  end

  describe 'associations' do
    specify(:aggregate_failures) do
      is_expected.to belong_to(:admin)
      is_expected.to belong_to(:api_key).optional
    end
  end

  describe 'enums' do
    specify(:aggregate_failures) do
      expect(described_class.categories).to eq(
        'description' => 0,
        'missing_filter' => 1,
        'missing_field' => 2,
        'missing_resource' => 3,
        'serialization' => 4,
        'other' => 5
      )
      expect(described_class.statuses).to eq('pending' => 0, 'accepted' => 1, 'rejected' => 2, 'shipped' => 3)
    end
  end
end
