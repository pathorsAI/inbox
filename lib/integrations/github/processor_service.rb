# Opens a GitHub issue whenever the team raises a ticket, so engineering picks the
# case up in the tracker it already works out of instead of watching the inbox.
#
# The issue is a handoff, not an archive: it carries just enough context to act on,
# and links back to the conversation for the rest of the thread.
class Integrations::Github::ProcessorService
  include ::Rails.application.routes.url_helpers

  ISSUES_URL = 'https://api.github.com/repos/%<repository>s/issues'.freeze
  DESCRIPTION_LIMIT = 500

  pattr_initialize [:hook!, :event_name!, :event_data!]

  def perform
    return unless issue_wanted?

    response = create_issue
    return hook.prompt_reauthorization! if access_lost?(response)
    return log_failure(response) unless response.success?

    record_issue(response.parsed_response)
  rescue Integrations::Github::AppClient::AuthorizationError => e
    Rails.logger.warn("GitHub installation #{hook.reference_id} refused hook #{hook.id}: #{e.message}")
    hook.prompt_reauthorization!
  end

  private

  def issue_wanted?
    return false unless event_name == 'ticket.created'
    # Not installed through the app yet (a hook left over from the old token
    # setup), no repository picked, or GitHub already told us the installation
    # is gone: nothing to do until an admin finishes the setup.
    return false if hook.reference_id.blank? || settings[:repository].blank? || hook.reauthorization_required?

    # The event can reach us more than once (job re-enqueue, replayed dispatch);
    # a case that already has an issue must not get a second one.
    conversation.additional_attributes['github_issue'].blank?
  end

  def ticket
    event_data[:ticket]
  end

  def conversation
    @conversation ||= ticket.conversation
  end

  def settings
    @settings ||= hook.settings.to_h.with_indifferent_access
  end

  def create_issue
    HTTParty.post(
      format(ISSUES_URL, repository: settings[:repository]),
      headers: {
        'Authorization' => "Bearer #{installation_token}",
        'Accept' => 'application/vnd.github+json',
        'X-GitHub-Api-Version' => Integrations::Github::AppClient::API_VERSION,
        'Content-Type' => 'application/json'
      },
      body: issue_payload.to_json
    )
  end

  def installation_token
    Integrations::Github::AppClient.new.installation_token(hook.reference_id, repository: settings[:repository])
  end

  def issue_payload
    payload = { title: ticket.subject, body: issue_body }
    payload[:labels] = [settings[:label]] if settings[:label].present?
    payload
  end

  def issue_body
    details = {
      contact: contact_description,
      ticket_type: ticket.ticket_type,
      due_at: ticket.due_at&.to_fs(:long),
      conversation: conversation_url
    }.compact_blank

    summary = details.map { |key, value| "**#{I18n.t("integration_apps.github.issue.#{key}")}:** #{value}" }.join("\n")
    [summary, first_incoming_message_content].compact_blank.join("\n\n")
  end

  def contact_description
    contact = conversation.contact
    return contact.name if contact.email.blank?

    "#{contact.name} <#{contact.email}>"
  end

  def first_incoming_message_content
    conversation.messages.incoming.first&.content&.truncate(DESCRIPTION_LIMIT)
  end

  def conversation_url
    app_account_conversation_url(account_id: conversation.account_id, id: conversation.display_id)
  end

  def record_issue(issue)
    conversation.additional_attributes['github_issue'] = {
      'url' => issue['html_url'],
      'number' => issue['number'],
      'repository' => settings[:repository]
    }
    conversation.save!

    conversation.messages.create!(
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :outgoing,
      private: true,
      content: I18n.t('integration_apps.github.issue_created_note', url: issue['html_url'])
    )
  end

  # Uninstalled, suspended, or the repository left the installation. A 403 that
  # carries rate-limit headers is throttling, which passes on its own.
  def access_lost?(response)
    return true if [401, 404].include?(response.code)

    response.code == 403 && response.headers['retry-after'].blank? && response.headers['x-ratelimit-remaining'] != '0'
  end

  def log_failure(response)
    Rails.logger.error("GitHub issue creation failed for hook #{hook.id} on #{settings[:repository]}: #{response.code} #{response.body}")
  end
end
