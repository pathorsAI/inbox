module SuperAdmin::AccountFeaturesHelper
  def self.account_features
    YAML.safe_load(Rails.root.join('config/features.yml').read).freeze
  end

  def self.account_premium_features
    account_features.filter { |feature| feature['premium'] }.pluck('name')
  end

  # Returns a hash mapping feature names to their display names
  def self.feature_display_names
    account_features.each_with_object({}) do |feature, hash|
      hash[feature['name']] = feature['display_name']
    end
  end

  def self.filter_internal_features(features)
    return features if ChatwootApp.chatwoot_cloud?

    internal_features = account_features.select { |f| f['chatwoot_internal'] }.pluck('name')
    features.except(*internal_features)
  end

  def self.filter_deprecated_features(features)
    deprecated_features = account_features.select { |f| f['deprecated'] }.pluck('name')
    features.except(*deprecated_features)
  end

  # Pathors fork: premium features are Chatwoot's paid Enterprise product. This
  # installation resells the Community Edition, so they are never listed and
  # never toggleable — SuperAdmin::AccountsController drops them from updates.
  def self.filter_premium_features(features)
    features.except(*account_premium_features)
  end

  def self.sort_and_transform_features(features, display_names)
    features.sort_by { |key, _| display_names[key] || key }
            .to_h
            .transform_keys { |key| [key, display_names[key]] }
  end

  # Returns a [regular, premium] pair to keep the shape callers destructure.
  # Premium is always empty here — see filter_premium_features.
  def self.partition_features(features)
    filtered = filter_internal_features(features)
    filtered = filter_deprecated_features(filtered)
    filtered = filter_premium_features(filtered)

    [sort_and_transform_features(filtered, feature_display_names), {}]
  end

  def self.filtered_features(features)
    partition_features(features).first
  end
end
