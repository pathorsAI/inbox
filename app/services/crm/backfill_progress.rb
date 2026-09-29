# A CRM backfill's progress, in Redis so the settings page can poll it while
# Crm::BackfillJob runs. The running flag doubles as the one-run-per-hook
# lock; the job keeps it alive, so a run whose worker died stops counting as
# running within RUNNING_TTL.
class Crm::BackfillProgress
  COUNTERS = %w[linked refreshed ambiguous no_match errors].freeze
  RUNNING_TTL = 1.hour
  KEEP_FOR = 7.days

  pattr_initialize :hook

  # false when a run is already going.
  def start!(total)
    return false unless Redis::Alfred.set(running_key, 1, nx: true, ex: RUNNING_TTL.to_i)

    save({ 'state' => 'running', 'total' => total, 'processed' => 0, **COUNTERS.index_with(0),
           'started_at' => Time.current.iso8601, 'finished_at' => nil })
    true
  end

  def running?
    Redis::Alfred.exists?(running_key)
  end

  # result: one of COUNTERS, or nil for a contact skipped
  def advance(result)
    data['processed'] += 1
    data[result.to_s] += 1 if result
    save(data)
    Redis::Alfred.expire(running_key, RUNNING_TTL.to_i)
  end

  def finish!
    save(data.merge('state' => 'finished', 'finished_at' => Time.current.iso8601))
    Redis::Alfred.delete(running_key)
  end

  def counts
    data.slice(*COUNTERS)
  end

  # The body of GET …/crm_backfill.
  def status
    stored = data.presence || { 'state' => 'idle', 'total' => 0, 'processed' => 0, **COUNTERS.index_with(0),
                                'started_at' => nil, 'finished_at' => nil }
    # A run whose worker died never wrote its finish.
    stored = stored.merge('state' => 'finished') if stored['state'] == 'running' && !running?
    stored
  end

  private

  def data
    @data ||= JSON.parse(Redis::Alfred.get(progress_key) || '{}')
  end

  def save(value)
    @data = value
    Redis::Alfred.set(progress_key, value.to_json, ex: KEEP_FOR.to_i)
  end

  def progress_key
    format(Redis::Alfred::CRM_BACKFILL_PROGRESS, hook_id: hook.id)
  end

  def running_key
    format(Redis::Alfred::CRM_BACKFILL_RUNNING, hook_id: hook.id)
  end
end
