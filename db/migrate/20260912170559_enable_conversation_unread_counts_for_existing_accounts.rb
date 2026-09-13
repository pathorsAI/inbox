class EnableConversationUnreadCountsForExistingAccounts < ActiveRecord::Migration[7.1]
  FEATURES = %w[conversation_unread_counts unread_count_for_filters].freeze

  def up
    # features.yml now ships both flags enabled, but ConfigLoader only ever adds
    # new flags to ACCOUNT_LEVEL_FEATURE_DEFAULTS — it never flips an existing
    # one — so new signups need the stored defaults updated here too.
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    if config&.value.present?
      config.value = config.value.map do |feature|
        FEATURES.include?(feature['name']) ? feature.merge('enabled' => true) : feature
      end
      config.save!
      GlobalConfig.clear_cache
    end

    Account.find_in_batches(batch_size: 100) do |accounts|
      accounts.each { |account| account.enable_features!(*FEATURES) }
    end
  end
end
