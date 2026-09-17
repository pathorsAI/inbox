require 'rails_helper'

RSpec.describe Email::SenderTriageService do
  let(:account) { create(:account) }
  let(:channel) { instance_double(Channel::Email, newsletter_filter_enabled: true) }
  let(:body_text) { '' }
  let(:body_links) { [] }
  let(:processed_mail) do
    instance_double(MailPresenter, bounced?: false, auto_reply?: false, newsletter?: false, body_text: body_text, body_links: body_links)
  end

  def triage(sender_email)
    described_class.new(account: account, channel: channel, processed_mail: processed_mail, sender_email: sender_email).perform
  end

  describe 'notification senders' do
    it 'parks the classic no-reply mailboxes' do
      expect(triage('no-reply@accounts.google.com')).to eq('filtered' => 'notification')
      expect(triage('comments-noreply@example.com')).to eq('filtered' => 'notification')
      expect(triage('donotreply@example.com')).to eq('filtered' => 'notification')
    end

    it 'parks reply-to, notification, alert and mailer mailboxes' do
      expect(triage('b2b_replyto@sinopac.com')).to eq('filtered' => 'notification')
      expect(triage('notifications@github.com')).to eq('filtered' => 'notification')
      expect(triage('notify@stripe.com')).to eq('filtered' => 'notification')
      expect(triage('alerts@grafana.net')).to eq('filtered' => 'notification')
      expect(triage('mailer@example.com')).to eq('filtered' => 'notification')
      expect(triage('automated@example.com')).to eq('filtered' => 'notification')
    end

    it 'leaves people and VERP bounce senders alone' do
      expect(triage('jack@pathors.com')).to eq({})
      expect(triage('service@example.com')).to eq({})
      expect(triage('bounce+token@example.com')).to eq({})
      expect(triage('replytoall@example.com')).to eq({})
    end
  end

  describe 'list headers' do
    let(:processed_mail) do
      instance_double(MailPresenter, bounced?: false, auto_reply?: false, newsletter?: true, newsletter_matches: ['list_unsubscribe'])
    end

    it 'parks the mail as a newsletter and records the headers that matched' do
      expect(triage('news@example.com')).to eq('filtered' => 'newsletter', 'filter_matches' => ['list_unsubscribe'])
    end
  end

  describe 'body markers' do
    context 'with an event invite whose footer links opt out of the host and unsubscribe from everything' do
      let(:body_text) { 'Jack invited you to Dinner at the harbour on Friday. RSVP on Partiful.' }
      let(:body_links) do
        ['Opt out of invites from this host https://partiful.com/opt-out/abc', 'unsubscribe https://partiful.com/unsubscribe/abc']
      end

      it 'parks the mail as a newsletter' do
        expect(triage('invites@partiful-mail.com')).to eq('filtered' => 'newsletter', 'filter_matches' => ['unsubscribe_link'])
      end
    end

    context 'with a billing notice that says it is automated and not to reply' do
      let(:body_text) do
        "Your Soniox Account Pathors has been charged $30.00 based on your Autopay settings.\n\n" \
          'This is an automated message from Soniox. Please do not reply to this email.'
      end

      it 'parks the mail as a notification and records every marker that matched' do
        expect(triage('cloud@soniox.com')).to eq('filtered' => 'notification', 'filter_matches' => %w[do_not_reply automated_message])
      end
    end

    context 'with a designed mail carrying a dozen links and no footer phrases' do
      let(:body_links) { (1..12).map { |index| "Item #{index} https://example.com/#{index}" } }

      it 'parks the mail as a newsletter on link count alone' do
        expect(triage('hello@example.com')).to eq('filtered' => 'newsletter', 'filter_matches' => ['link_heavy'])
      end
    end

    context 'with a person asking to be unsubscribed in their own words' do
      let(:body_text) { 'Hi, please unsubscribe me from your mailing list. If you do not reply by Friday I will call.' }
      let(:body_links) { ['our site https://example.com'] }

      it 'leaves the mail in the inbox' do
        expect(triage('jack@example.com')).to eq({})
      end
    end

    context 'when the inbox has the filter switched off' do
      let(:channel) { instance_double(Channel::Email, newsletter_filter_enabled: false) }
      let(:body_text) { 'This is an automated message from Soniox. Please do not reply to this email.' }

      it 'leaves the mail in the inbox' do
        expect(triage('cloud@soniox.com')).to eq({})
      end
    end
  end

  describe 'sender lists' do
    it 'parks blocked domains before any header heuristics' do
      SenderListEntry.create!(account: account, value: 'sinopac.com', list_type: :blocked)
      expect(triage('cardauthservice@sinopac.com')).to eq('sender_list' => 'blocked', 'filtered' => 'blocklist')
    end
  end
end
