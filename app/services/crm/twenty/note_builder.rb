# Title and markdown body of the notes this integration writes to Twenty, in
# the account's language and time zone.
class Crm::Twenty::NoteBuilder
  include ::Rails.application.routes.url_helpers

  TITLE_LENGTH = 80
  # Twenty stores the body as rich text with no documented cap; this keeps a
  # long email thread readable in the note panel. The link covers the rest.
  TRANSCRIPT_LIMIT = 12_000

  def initialize(account)
    @account = account
    @zone = Time.find_zone(account.reporting_timezone) || Time.zone
  end

  def contact_note(note)
    I18n.with_locale(@account.locale) do
      first_line = note.content.to_s.lines.first.to_s.gsub(/[#>*_`\[\]]/, '').strip
      footer = I18n.t('integration_apps.twenty.contact_note_footer',
                      author: note.user&.name || brand_name, brand_name: brand_name, url: contact_url(note.contact))
      {
        title: first_line.presence&.truncate(TITLE_LENGTH) || I18n.t('integration_apps.twenty.untitled_note'),
        markdown: "#{note.content}\n\n---\n\n#{footer}"
      }
    end
  end

  def conversation_note(conversation)
    I18n.with_locale(@account.locale) do
      scope = 'integration_apps.twenty.conversation_note'
      header = I18n.t("#{scope}.header", display_id: conversation.display_id, inbox_name: conversation.inbox.name,
                                         url: conversation_url(conversation), started_at: stamp(conversation.created_at),
                                         resolved_at: stamp(Time.current))
      {
        title: I18n.t("#{scope}.title", brand_name: brand_name, display_id: conversation.display_id, inbox_name: conversation.inbox.name),
        markdown: [header, *transcript(conversation)].join("\n\n")
      }
    end
  end

  private

  # Newest messages first until the limit, then printed oldest first.
  def transcript(conversation)
    messages = conversation.messages.where(message_type: %i[incoming outgoing]).includes(:sender, :attachments).order(:created_at).to_a
    kept = []
    size = 0
    messages.reverse_each do |message|
      block = message_block(message)
      break if size + block.length > TRANSCRIPT_LIMIT

      kept.unshift(block)
      size += block.length
    end
    omitted = messages.size - kept.size
    omitted.positive? ? [I18n.t('integration_apps.twenty.conversation_note.omitted', count: omitted), *kept] : kept
  end

  def message_block(message)
    heading = "**#{message.sender&.name.presence || brand_name}** · #{stamp(message.created_at)}"
    heading += " · _#{I18n.t('integration_apps.twenty.conversation_note.internal_note')}_" if message.private?
    lines = message.content.to_s.strip.lines.map(&:rstrip)
    lines += message.attachments.map { |attachment| I18n.t('integration_apps.twenty.conversation_note.attachment', type: attachment.file_type) }
    ([heading] + lines.map { |line| "> #{line}" }).join("\n")
  end

  def stamp(time)
    time.in_time_zone(@zone).strftime('%Y-%m-%d %H:%M')
  end

  def conversation_url(conversation)
    app_account_conversation_url(account_id: conversation.account_id, id: conversation.display_id)
  end

  def contact_url(contact)
    "#{ENV.fetch('FRONTEND_URL', '')}/app/accounts/#{contact.account_id}/contacts/#{contact.id}"
  end

  def brand_name
    ::GlobalConfig.get('BRAND_NAME')['BRAND_NAME'] || 'Chatwoot'
  end
end
