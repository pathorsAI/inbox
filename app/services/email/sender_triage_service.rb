# Classifies an inbound email sender into a triage lane and returns the
# conversation `additional_attributes` describing that lane. Returns an empty
# hash for the default lane so ordinary conversations stay untouched.
#
# Keys are strings on purpose: Conversation reads them back in before_create,
# where the jsonb attribute has not been round-tripped through the database yet.
class Email::SenderTriageService
  BYPASS_LISTS = %w[vip allowed].freeze

  # Local parts that only ever send machine-generated mail. `no-reply` variants are
  # matched after a separator too (`comments-noreply@`), and so are the other machine
  # mailboxes banks and SaaS tools send from (`b2b_replyto@`, `notifications@`,
  # `alerts@`). Daemon addresses must be exact so VERP-style `bounce+token@` senders
  # from real systems are left alone.
  NOTIFICATION_SENDER_PATTERN = /
    \A(?:mailer-daemon|postmaster)\z
    |(?:\A|[-._+])(?:no[-._]?reply|do[-._]?not[-._]?reply)
    |(?:\A|[-._+])(?:reply[-._]?to|notifications?|notify|alerts?|mailer|automated)(?=\z|[-._+\d])
  /xi

  # Footer boilerplate and layout that mark machine-sent mail, in priority order: the first match picks the
  # lane. Link markers match an anchor's label or URL rather than free text, so a customer who writes
  # "please unsubscribe me" is not parked; the text markers are phrases people do not write to a help desk.
  BODY_MARKERS = [
    { name: 'unsubscribe_link', lane: 'newsletter', on: :body_links, pattern: /unsubscribe|opt[ _-]?out|取消訂閱|退訂/i },
    { name: 'preferences_link', lane: 'newsletter', on: :body_links,
      pattern: /(email|notification|subscription|communication)[ _-]?preferences|manage[ _-]?preferences/i },
    { name: 'view_in_browser_link', lane: 'newsletter', on: :body_links,
      pattern: /view[ _-]?(this[ _-]?|it[ _-]?)?(e-?mail[ _-]?|message[ _-]?)?(in[ _-]?(your[ _-]?)?(web[ _-]?)?browser|online)|在瀏覽器/i },
    { name: 'link_heavy', lane: 'newsletter', on: :body_links, pattern: %r{ https?://}, min: 10 },
    { name: 'receiving_because', lane: 'newsletter', on: :body_text,
      pattern: /you('re| are) receiving this|you received this (e-?mail|message) because/i },
    { name: 'do_not_reply', lane: 'notification', on: :body_text,
      pattern: /(do not|don'?t) reply (to|directly)|not monitored|請勿(直接)?回覆/i },
    { name: 'automated_message', lane: 'notification', on: :body_text,
      pattern: /automated (message|e-?mail|notification)|automatically generated|(generated|sent) automatically|系統自動|自動(發送|寄送)/i }
  ].freeze

  pattr_initialize [:account!, :channel!, :processed_mail!, :sender_email!]

  def perform
    attributes = {}
    attributes['sender_list'] = sender_list if sender_list.present?
    attributes.merge(filter_attributes)
  end

  private

  def sender_list
    return @sender_list if defined?(@sender_list)

    @sender_list = SenderListEntry.list_type_for(account: account, email: sender_email)
  end

  def filter_attributes
    return { 'filtered' => 'blocklist' } if sender_list == 'blocked'
    return {} if BYPASS_LISTS.include?(sender_list)
    return {} unless channel.newsletter_filter_enabled

    automated_mail_attributes || newsletter_attributes || body_marker_attributes || {}
  end

  # Bounce is checked first because delivery reports routinely carry list/auto-reply
  # headers from the original message and would otherwise land in the wrong lane.
  def automated_mail_attributes
    return { 'filtered' => 'bounce' } if processed_mail.bounced?
    return { 'filtered' => 'auto_reply' } if processed_mail.auto_reply?

    { 'filtered' => 'notification' } if notification_sender?
  end

  def newsletter_attributes
    return unless processed_mail.newsletter?

    { 'filtered' => 'newsletter', 'filter_matches' => processed_mail.newsletter_matches }
  end

  # Mail with no sender or header marker that still reads like machine mail from its footer or layout.
  def body_marker_attributes
    matches = BODY_MARKERS.select { |marker| body_marker?(marker) }
    return if matches.empty?

    { 'filtered' => matches.first[:lane], 'filter_matches' => matches.pluck(:name) }
  end

  def body_marker?(marker)
    Array(processed_mail.public_send(marker[:on])).count { |value| value.match?(marker[:pattern]) } >= marker.fetch(:min, 1)
  end

  def notification_sender?
    sender_email.to_s.split('@').first.to_s.match?(NOTIFICATION_SENDER_PATTERN)
  end
end
