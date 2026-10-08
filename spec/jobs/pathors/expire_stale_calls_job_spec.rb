require 'rails_helper'

RSpec.describe Pathors::ExpireStaleCallsJob do
  let(:message) { create(:message, content_type: 'voice_call') }
  let!(:stale_call) do
    create(:call, :pathors, conversation: message.conversation, message: message, started_at: 3.hours.ago)
  end

  it 'ends a Pathors call still live past the maximum call duration' do
    described_class.perform_now

    expect(stale_call.reload).to have_attributes(status: 'completed', end_reason: 'stale', ended_at: nil)
  end

  it 'touches the call message so dashboards drop it from the live list' do
    expect { described_class.perform_now }.to(change { message.reload.updated_at })
  end

  it 'leaves recent, ended and non-Pathors calls alone' do
    recent = create(:call, :pathors, started_at: 30.minutes.ago)
    ended = create(:call, :pathors, status: 'failed', started_at: 3.hours.ago)
    twilio = create(:call, status: 'in_progress', started_at: 3.hours.ago)

    described_class.perform_now

    expect([recent, ended, twilio].map { |call| call.reload.status }).to eq(%w[in_progress failed in_progress])
  end
end
