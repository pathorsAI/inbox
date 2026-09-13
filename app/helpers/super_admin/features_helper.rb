module SuperAdmin::FeaturesHelper
  # Pathors fork: entries flagged `enterprise` describe Chatwoot's paid Edition.
  # This installation resells the Community Edition, so those cards (and the
  # upgrade prompts that came with them) are never listed.
  def self.available_features
    features = YAML.load(ERB.new(Rails.root.join('app/helpers/super_admin/features.yml').read).result).with_indifferent_access

    features.reject { |_feature, attrs| attrs[:enterprise] }
  end

  def self.plan_details
    plan = ChatwootHub.pricing_plan
    quantity = ChatwootHub.pricing_plan_quantity

    if plan == 'premium'
      "You are currently on the <span class='font-semibold'>#{plan}</span> plan with <span class='font-semibold'>#{quantity} agents</span>."
    else
      "You are currently on the <span class='font-semibold'>#{plan}</span> edition plan."
    end
  end
end
