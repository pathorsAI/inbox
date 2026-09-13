require 'rails_helper'

RSpec.describe SuperAdmin::AccountFeaturesHelper do
  let(:account) { create(:account) }
  let(:premium_features) { described_class.account_premium_features }

  describe '.partition_features' do
    it 'never reports a premium feature' do
      regular, premium = described_class.partition_features(account.all_features)

      expect(premium).to be_empty
      expect(regular.keys.map(&:first) & premium_features).to be_empty
    end

    it 'keeps the features this fork ships itself' do
      regular, = described_class.partition_features(account.all_features)

      expect(regular.keys.map(&:first)).to include('tickets', 'channel_voice')
    end
  end

  describe '.filtered_features' do
    it 'excludes premium features' do
      feature_names = described_class.filtered_features(account.all_features).keys.map(&:first)

      expect(feature_names & premium_features).to be_empty
    end
  end
end
