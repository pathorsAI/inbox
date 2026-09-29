# Short-lived Twenty reads shared by the web and Sidekiq processes. Rails.cache
# is per-process in production, so a note synced by a job could not expire the
# card the sidebar cached; Redis is shared.
module Crm::Twenty::Cache
  PREFIX = 'TWENTY_CRM'.freeze

  def self.key(hook, *parts)
    [PREFIX, hook.id, *parts].join('::')
  end

  def self.fetch(hook, *parts, ttl:)
    cached = Redis::Alfred.get(key(hook, *parts))
    return JSON.parse(cached) if cached

    value = yield
    Redis::Alfred.setex(key(hook, *parts), value.to_json, ttl) unless value.nil?
    value
  end

  def self.write(hook, *parts, value:, ttl:)
    Redis::Alfred.setex(key(hook, *parts), value.to_json, ttl)
  end

  def self.read(hook, *parts)
    cached = Redis::Alfred.get(key(hook, *parts))
    JSON.parse(cached) if cached
  end

  def self.delete(hook, *parts)
    Redis::Alfred.delete(key(hook, *parts))
  end
end
