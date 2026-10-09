require 'rails_helper'

RSpec.describe 'Public Portal Tickets', type: :request do
  let!(:account) { create(:account) }
  let!(:web_widget) { create(:channel_widget, account: account) }
  let!(:portal) do
    create(:portal, slug: 'test-portal', account: account, custom_domain: 'www.example.com', channel_web_widget: web_widget)
  end
  let(:inbox) { web_widget.inbox }
  let(:contact) { create(:contact, account: account, email: 'customer@example.com') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:ticket) { create(:ticket, account: account, conversation: conversation, subject: 'Broken widget') }
  let(:token) { contact.signed_id(purpose: "portal_ticket_access_#{portal.id}", expires_in: 15.minutes) }

  before { account.enable_features!('tickets') }

  def sign_in_contact
    get "/hc/#{portal.slug}/tickets/verify", params: { token: token }
  end

  # The ticket routes carry no `:locale` segment, so the locale rides as a query
  # param. `set_portal_locale` used to overwrite it with the portal default: the
  # strings still translated (I18n.locale followed the param) but every link on
  # the page pointed back at the default locale, so choosing a language looked
  # like it bounced straight back.
  describe 'locale handling' do
    let!(:portal) do
      create(:portal, slug: 'test-portal', account: account, custom_domain: 'www.example.com',
                      channel_web_widget: web_widget, config: { allowed_locales: %w[en es], default_locale: 'en' })
    end

    let(:payload) do
      { name: 'Jane Doe', email: 'jane@example.com', subject: 'Cannot log in', ticket_type: 'issue', description: 'It keeps failing.' }
    end

    it 'keeps a published locale on the ticket links' do
      get "/hc/#{portal.slug}/tickets/new", params: { locale: 'es' }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("/hc/#{portal.slug}/tickets?locale=es")
    end

    it 'points the home link at the requested locale instead of the portal default' do
      get "/hc/#{portal.slug}/tickets/new", params: { locale: 'es' }

      expect(response.body).to include("href=\"/hc/#{portal.slug}/es\"")
      expect(response.body).not_to include("href=\"/hc/#{portal.slug}/en\"")
    end

    it 'falls back to the portal default for a locale the portal does not publish' do
      get "/hc/#{portal.slug}/tickets/new", params: { locale: 'zz' }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("href=\"/hc/#{portal.slug}/en\"")
      expect(response.body).not_to include('locale=zz')
    end

    it 'carries the locale through the submission redirect' do
      post "/hc/#{portal.slug}/tickets", params: payload.merge(locale: 'es')

      expect(response).to redirect_to("/hc/#{portal.slug}/tickets/new?locale=es")
    end

    it 'carries the locale through the access-link verification redirect' do
      get "/hc/#{portal.slug}/tickets/verify", params: { token: token, locale: 'es' }

      expect(response).to redirect_to("/hc/#{portal.slug}/tickets?locale=es")
    end

    it 'leaves the default locale out of the redirect so existing URLs are unchanged' do
      post "/hc/#{portal.slug}/tickets", params: payload

      expect(response).to redirect_to("/hc/#{portal.slug}/tickets/new")
    end
  end

  describe 'GET /hc/:slug/tickets/new' do
    it 'renders the submission form' do
      get "/hc/#{portal.slug}/tickets/new"

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Submit a ticket')
    end

    context 'when the portal has no web widget' do
      before { portal.update!(channel_web_widget: nil) }

      it 'returns not found' do
        get "/hc/#{portal.slug}/tickets/new"

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when the tickets feature is disabled' do
      before { account.disable_features!('tickets') }

      it 'returns not found' do
        get "/hc/#{portal.slug}/tickets/new"

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /hc/:slug/tickets' do
    let(:payload) do
      { name: 'Jane Doe', email: 'jane@example.com', subject: 'Cannot log in', ticket_type: 'issue', description: 'It keeps failing.' }
    end

    let(:png) { fixture_file_upload(Rails.root.join('spec/assets/sample.png'), 'image/png') }
    let(:pdf) { fixture_file_upload(Rails.root.join('spec/assets/sample.pdf'), 'application/pdf') }

    it 'creates a contact, a conversation and a ticket in the widget inbox' do
      expect { post "/hc/#{portal.slug}/tickets", params: payload }.to change(Ticket, :count).by(1)

      created_ticket = Ticket.last
      expect(created_ticket.subject).to eq('Cannot log in')
      expect(created_ticket.ticket_type).to eq('issue')
      expect(created_ticket.conversation.inbox_id).to eq(inbox.id)
      expect(created_ticket.conversation.contact.email).to eq('jane@example.com')
      expect(created_ticket.conversation.messages.incoming.last.content).to eq("**Cannot log in**\n\nIt keeps failing.")
    end

    it 'answers the customer with an acknowledgement that quotes their request' do
      post "/hc/#{portal.slug}/tickets", params: payload

      conversation = Ticket.last.conversation
      acknowledgement = conversation.messages.outgoing.last
      expect(acknowledgement.content).to include("ticket ##{conversation.display_id}")
      expect(acknowledgement.content).to include('Subject: Cannot log in')
      expect(acknowledgement.content).to include('It keeps failing.')
      # No sender, so reporting still sees a conversation nobody has answered.
      expect(acknowledgement.sender).to be_nil
      expect(conversation.first_reply_created_at).to be_nil
    end

    it 'strips line breaks out of the subject' do
      post "/hc/#{portal.slug}/tickets", params: payload.merge(subject: "Cannot log in\r\nBcc: attacker@example.com")

      expect(Ticket.last.subject).to eq('Cannot log in Bcc: attacker@example.com')
    end

    it 'redirects back to the form with the reference in the flash' do
      post "/hc/#{portal.slug}/tickets", params: payload

      expect(response).to redirect_to("/hc/#{portal.slug}/tickets/new")
      expect(flash[:portal_ticket_created]).to eq(Ticket.last.conversation.display_id)
      expect(flash[:portal_ticket_email]).to eq('jane@example.com')
    end

    it 'stores the uploaded files on the description message' do
      post "/hc/#{portal.slug}/tickets", params: payload.merge(attachments: [png, pdf])

      attachments = Ticket.last.conversation.messages.incoming.last.attachments
      expect(attachments.count).to eq(2)
      expect(attachments.map(&:file_type)).to contain_exactly('image', 'file')
      expect(attachments.map { |attachment| attachment.file.filename.to_s }).to contain_exactly('sample.png', 'sample.pdf')
    end

    it 'rejects a submission with more attachments than the limit' do
      files = Array.new(11) { fixture_file_upload(Rails.root.join('spec/assets/sample.pdf'), 'application/pdf') }

      expect { post "/hc/#{portal.slug}/tickets", params: payload.merge(attachments: files) }.not_to change(Ticket, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include('You can attach up to 10 files.')
    end

    it 'rejects an attachment over the size limit' do
      oversized = fixture_file_upload(Rails.root.join('spec/assets/large_file.pdf'), 'application/pdf')

      expect { post "/hc/#{portal.slug}/tickets", params: payload.merge(attachments: [oversized]) }.not_to change(Ticket, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include('large_file.pdf is larger than 10 MB.')
    end

    it 'rejects an attachment with an unsupported content type' do
      executable = fixture_file_upload(Rails.root.join('spec/assets/sample.pdf'), 'application/x-msdownload')

      expect { post "/hc/#{portal.slug}/tickets", params: payload.merge(attachments: [executable]) }.not_to change(Ticket, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include('sample.pdf is not a supported file type.')
    end

    it 'reuses an existing contact with the same email' do
      contact

      expect do
        post "/hc/#{portal.slug}/tickets", params: payload.merge(email: contact.email)
      end.not_to change(Contact, :count)

      expect(Ticket.last.conversation.contact_id).to eq(contact.id)
    end

    it 'rejects a submission without a subject' do
      expect { post "/hc/#{portal.slug}/tickets", params: payload.merge(subject: '') }.not_to change(Ticket, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include('Enter a subject.')
    end

    it 'rejects a submission without a type' do
      expect { post "/hc/#{portal.slug}/tickets", params: payload.merge(ticket_type: '') }.not_to change(Ticket, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include('Choose a type.')
    end

    it 'rejects a submission with an invalid email' do
      expect { post "/hc/#{portal.slug}/tickets", params: payload.merge(email: 'not-an-email') }.not_to change(Ticket, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include('Enter a valid email address.')
    end

    context 'when the tickets feature is disabled' do
      before { account.disable_features!('tickets') }

      it 'returns not found' do
        expect { post "/hc/#{portal.slug}/tickets", params: payload }.not_to change(Ticket, :count)

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when the portal points at an email inbox' do
      let(:email_inbox) { create(:channel_email, account: account).inbox }

      before { portal.update!(config: { ticket_inbox_id: email_inbox.id }) }

      it 'creates the conversation in the email inbox keyed by the email address' do
        post "/hc/#{portal.slug}/tickets", params: payload

        created_ticket = Ticket.last
        expect(created_ticket.conversation.inbox_id).to eq(email_inbox.id)
        expect(created_ticket.conversation.contact_inbox.source_id).to eq('jane@example.com')
      end

      it 'sends the acknowledgement to the customer so their reply threads onto the ticket' do
        post "/hc/#{portal.slug}/tickets", params: payload

        conversation = Ticket.last.conversation
        acknowledgement = conversation.messages.outgoing.last
        expect(SendReplyJob).to have_been_enqueued.with(acknowledgement.id)
        # Rendered here rather than through the delivery the job performs: with SMTP_ADDRESS unset
        # the mailer initializer switches the test environment to :sendmail, and nothing reaches
        # ActionMailer::Base.deliveries.
        mail = with_modified_env SMTP_ADDRESS: 'smtp.example.com' do
          ConversationReplyMailer.with(account: account).email_reply(acknowledgement).message
        end

        expect(mail.to).to eq(['jane@example.com'])
        expect(mail.body.encoded).to include('It keeps failing.')
        expect(mail.message_id).to start_with("conversation/#{conversation.uuid}/messages/")
      end

      it 'stores the subject as the mail subject the reply mailer sends on' do
        post "/hc/#{portal.slug}/tickets", params: payload

        expect(Ticket.last.conversation.additional_attributes['mail_subject']).to eq('Cannot log in')
      end

      it 'puts the subject in the email meta and leaves the body unprefixed' do
        post "/hc/#{portal.slug}/tickets", params: payload

        message = Ticket.last.conversation.messages.incoming.last
        expect(message.content_attributes['email']['subject']).to eq('Cannot log in')
        expect(message.content).to eq('It keeps failing.')
      end

      it 'reuses the contact inbox of an existing contact with the same email' do
        existing = create(:contact, account: account, email: 'jane@example.com')
        existing_contact_inbox = create(:contact_inbox, contact: existing, inbox: email_inbox, source_id: 'jane@example.com')

        expect { post "/hc/#{portal.slug}/tickets", params: payload }.not_to change(ContactInbox, :count)

        expect(Ticket.last.conversation.contact_inbox_id).to eq(existing_contact_inbox.id)
      end

      it 'creates a fresh conversation even when the inbox locks to a single conversation' do
        email_inbox.update!(lock_to_single_conversation: true)
        existing = create(:contact, account: account, email: 'jane@example.com')
        existing_contact_inbox = create(:contact_inbox, contact: existing, inbox: email_inbox, source_id: 'jane@example.com')
        existing_conversation = create(:conversation, account: account, inbox: email_inbox, contact: existing,
                                                      contact_inbox: existing_contact_inbox)

        expect { post "/hc/#{portal.slug}/tickets", params: payload }.to change(Ticket, :count).by(1)
        expect { post "/hc/#{portal.slug}/tickets", params: payload }.to change(Ticket, :count).by(1)

        expect(Ticket.count).to eq(2)
        expect(Ticket.distinct.pluck(:conversation_id).size).to eq(2)
        expect(existing_conversation.reload.ticket).to be_nil
      end
    end
  end

  describe 'POST /hc/:slug/tickets/access' do
    it 'sends an access link when the email belongs to a contact' do
      contact

      expect do
        post "/hc/#{portal.slug}/tickets/access", params: { email: contact.email }
      end.to have_enqueued_mail(PortalTicketAccessMailer, :access_link)

      # Turbo only renders form responses that redirect, so the confirmation lives on a GET page.
      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to("/hc/#{portal.slug}/tickets/access/sent")
    end

    it 'returns the same response without sending an email for an unknown address' do
      expect do
        post "/hc/#{portal.slug}/tickets/access", params: { email: 'nobody@example.com' }
      end.not_to have_enqueued_mail(PortalTicketAccessMailer, :access_link)

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to("/hc/#{portal.slug}/tickets/access/sent")
    end
  end

  describe 'GET /hc/:slug/tickets/access/sent' do
    it 'renders the check-your-inbox confirmation' do
      get "/hc/#{portal.slug}/tickets/access/sent"

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Check your inbox')
    end
  end

  describe 'GET /hc/:slug/tickets/verify' do
    it 'signs the contact in and redirects to the ticket list' do
      get "/hc/#{portal.slug}/tickets/verify", params: { token: token }

      expect(response).to redirect_to("/hc/#{portal.slug}/tickets")
    end

    it 'rejects a malformed token' do
      get "/hc/#{portal.slug}/tickets/verify", params: { token: 'nonsense' }

      expect(response).to have_http_status(:unauthorized)
      expect(response.body).to include('This link has expired or is not valid.')
    end

    it 'rejects an expired token' do
      expired_token = contact.signed_id(purpose: "portal_ticket_access_#{portal.id}", expires_in: 15.minutes)

      travel_to(20.minutes.from_now) do
        get "/hc/#{portal.slug}/tickets/verify", params: { token: expired_token }
      end

      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects a token minted for another portal' do
      other_portal = create(:portal, slug: 'other-portal', account: account, channel_web_widget: web_widget)
      other_token = contact.signed_id(purpose: "portal_ticket_access_#{other_portal.id}", expires_in: 15.minutes)

      get "/hc/#{portal.slug}/tickets/verify", params: { token: other_token }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /hc/:slug/tickets' do
    it 'redirects to the access page without a session' do
      get "/hc/#{portal.slug}/tickets"

      expect(response).to redirect_to("/hc/#{portal.slug}/tickets/access")
    end

    it 'lists the tickets of the signed in contact' do
      ticket
      sign_in_contact

      get "/hc/#{portal.slug}/tickets"

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Broken widget')
      expect(response.body).to include("##{conversation.display_id}")
    end

    it 'does not list tickets belonging to another contact' do
      other_conversation = create(:conversation, account: account, inbox: inbox)
      create(:ticket, account: account, conversation: other_conversation, subject: 'Somebody else problem')
      ticket
      sign_in_contact

      get "/hc/#{portal.slug}/tickets"

      expect(response.body).to include('Broken widget')
      expect(response.body).not_to include('Somebody else problem')
    end
  end

  describe 'GET /hc/:slug/tickets/:id' do
    it 'renders the ticket with its public messages' do
      create(:message, account: account, inbox: inbox, conversation: conversation, content: 'My widget is broken', message_type: :incoming)
      create(:message, account: account, inbox: inbox, conversation: conversation, content: 'Internal note', private: true)
      sign_in_contact

      get "/hc/#{portal.slug}/tickets/#{ticket.id}"

      expect(response).to have_http_status(:success)
      expect(response.body).to include('My widget is broken')
      expect(response.body).not_to include('Internal note')
    end

    it 'renders the attachments of a message' do
      message = build(:message, account: account, inbox: inbox, conversation: conversation, content: 'Here is the trace', message_type: :incoming)
      message.attachments.new(account_id: account.id, file_type: :file,
                              file: fixture_file_upload(Rails.root.join('spec/assets/sample.pdf'), 'application/pdf'))
      message.save!
      sign_in_contact

      get "/hc/#{portal.slug}/tickets/#{ticket.id}"

      expect(response).to have_http_status(:success)
      expect(response.body).to include('sample.pdf')
      expect(response.body).to include('/rails/active_storage')
    end

    it 'returns not found for a ticket belonging to another contact' do
      other_conversation = create(:conversation, account: account, inbox: inbox)
      other_ticket = create(:ticket, account: account, conversation: other_conversation)
      sign_in_contact

      get "/hc/#{portal.slug}/tickets/#{other_ticket.id}"

      expect(response).to have_http_status(:not_found)
    end

    it 'redirects to the access page without a session' do
      get "/hc/#{portal.slug}/tickets/#{ticket.id}"

      expect(response).to redirect_to("/hc/#{portal.slug}/tickets/access")
    end
  end
end
