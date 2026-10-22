# frozen_string_literal: true

require 'rails_helper'

RSpec.describe NotificationSetting do
  context 'with associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:user) }
  end

  describe 'Pathors push flags' do
    let(:setting) { described_class.create!(account: create(:account), user: create(:user)) }

    it 'stores the call attention flag next to the Chatwoot push flags' do
      setting.selected_push_flags = %i[push_conversation_assignment push_pathors_call_attention]
      setting.save!

      expect(setting.reload.selected_push_flags).to contain_exactly(:push_conversation_assignment, :push_pathors_call_attention)
      expect(setting.push_pathors_call_attention?).to be(true)
    end

    it 'keeps the flag off a bit any Chatwoot notification type uses' do
      expect(Notification::NOTIFICATION_TYPES.values).not_to include(*described_class::PATHORS_PUSH_FLAGS.keys)
    end
  end
end
