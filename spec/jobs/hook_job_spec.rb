require 'rails_helper'

RSpec.describe HookJob do
  subject(:job) { described_class.perform_later(hook, event_name, event_data) }

  let(:account) { create(:account) }
  let(:hook) { create(:integrations_hook, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:event_name) { 'message.created' }
  let(:event_data) { { message: create(:message, account: account, content: 'muchas muchas gracias', message_type: :incoming) } }

  it 'enqueues the job' do
    expect { job }.to have_enqueued_job(described_class)
      .with(hook, event_name, event_data)
      .on_queue('medium')
  end

  context 'when the hook is disabled' do
    it 'does not execute the job' do
      hook = create(:integrations_hook, status: 'disabled', account: account)
      allow(SendOnSlackJob).to receive(:perform_later)
      allow(Integrations::Dialogflow::ProcessorService).to receive(:new)
      allow(Integrations::GoogleTranslate::DetectLanguageService).to receive(:new)

      expect(SendOnSlackJob).not_to receive(:perform_later)
      expect(Integrations::GoogleTranslate::DetectLanguageService).not_to receive(:new)
      expect(Integrations::Dialogflow::ProcessorService).not_to receive(:new)
      described_class.perform_now(hook, event_name, event_data)
    end
  end

  context 'when handleable events like message.created' do
    let(:process_service) { double }

    before do
      allow(process_service).to receive(:perform)
    end

    it 'calls SendOnSlackJob when its a slack hook' do
      hook = create(:integrations_hook, app_id: 'slack', account: account)
      allow(SendOnSlackJob).to receive(:perform_later).and_return(process_service)
      expect(SendOnSlackJob).to receive(:perform_later).with(event_data[:message], hook)
      described_class.perform_now(hook, event_name, event_data)
    end

    it 'calls SendOnSlackJob when its a slack hook for message with attachments' do
      event_data = { message: create(:message, :with_attachment, account: account) }
      hook = create(:integrations_hook, app_id: 'slack', account: account)
      allow(SendOnSlackJob).to receive(:set).with(wait: 2.seconds).and_return(SendOnSlackJob)
      allow(SendOnSlackJob).to receive(:perform_later).and_return(process_service)
      expect(SendOnSlackJob).to receive(:perform_later).with(event_data[:message], hook)
      described_class.perform_now(hook, event_name, event_data)
    end

    it 'calls Integrations::Dialogflow::ProcessorService when its a dialogflow intergation' do
      hook = create(:integrations_hook, :dialogflow, inbox: inbox, account: account)
      allow(Integrations::Dialogflow::ProcessorService).to receive(:new).and_return(process_service)
      expect(Integrations::Dialogflow::ProcessorService).to receive(:new).with(event_name: event_name, hook: hook, event_data: event_data)
      described_class.perform_now(hook, event_name, event_data)
    end

    it 'calls Conversations::DetectLanguageJob when its a google_translate intergation' do
      hook = create(:integrations_hook, :google_translate, account: account)
      allow(Integrations::GoogleTranslate::DetectLanguageService).to receive(:new).and_return(process_service)
      expect(Integrations::GoogleTranslate::DetectLanguageService).to receive(:new).with(hook: hook, message: event_data[:message])
      described_class.perform_now(hook, event_name, event_data)
    end

    it "calls Integrations::Linear::AutoLinkService when it's a linear hook" do
      hook = create(:integrations_hook, :linear, account: account)
      allow(Integrations::Linear::AutoLinkService).to receive(:new).and_return(process_service)
      expect(Integrations::Linear::AutoLinkService).to receive(:new).with(account: account, message: event_data[:message])
      described_class.perform_now(hook, event_name, event_data)
    end
  end

  context 'when handleable events like message.updated for slack' do
    let(:process_service) { double }

    before do
      allow(process_service).to receive(:perform)
    end

    it 'calls UpdateSlackMessageJob when content_attributes changed' do
      message = create(:message, account: account, content: 'Pick one', message_type: :outgoing,
                                 content_type: :input_select, content_attributes: { items: [{ title: 'A', value: 'a' }] })
      hook = create(:integrations_hook, app_id: 'slack', account: account)
      event_data = { message: message, previous_changes: { 'content_attributes' => [{}, { 'submitted_values' => [{ 'title' => 'A' }] }] } }

      allow(UpdateSlackMessageJob).to receive(:perform_later).and_return(process_service)
      expect(UpdateSlackMessageJob).to receive(:perform_later).with(message, hook)
      described_class.perform_now(hook, 'message.updated', event_data)
    end

    it 'does not call UpdateSlackMessageJob when content_attributes did not change' do
      message = create(:message, account: account, content: 'Pick one', message_type: :outgoing,
                                 content_type: :input_select, content_attributes: { items: [{ title: 'A', value: 'a' }] })
      hook = create(:integrations_hook, app_id: 'slack', account: account)
      event_data = { message: message, previous_changes: { 'status' => %w[sent delivered] } }

      expect(UpdateSlackMessageJob).not_to receive(:perform_later)
      described_class.perform_now(hook, 'message.updated', event_data)
    end

    it 'does not call UpdateSlackMessageJob for unsupported content types' do
      message = create(:message, account: account, content: 'Hello', message_type: :outgoing, content_type: :text)
      hook = create(:integrations_hook, app_id: 'slack', account: account)
      event_data = { message: message, previous_changes: { 'content_attributes' => [{}, {}] } }

      expect(UpdateSlackMessageJob).not_to receive(:perform_later)
      described_class.perform_now(hook, 'message.updated', event_data)
    end
  end

  context 'when processing leadsquared integration' do
    let(:contact) { create(:contact, account: account) }
    let(:conversation) { create(:conversation, account: account, contact: contact) }
    let(:processor_service) { instance_double(Crm::Leadsquared::ProcessorService) }
    let(:leadsquared_hook) { instance_double(Integrations::Hook, id: 123, app_id: 'leadsquared', account: account) }

    before do
      allow(Crm::Leadsquared::ProcessorService).to receive(:new).with(leadsquared_hook).and_return(processor_service)
    end

    context 'when processing contact.updated event' do
      let(:event_name) { 'contact.updated' }
      let(:event_data) { { contact: contact } }

      it 'uses a lock when processing' do
        allow(leadsquared_hook).to receive(:disabled?).and_return(false)
        allow(leadsquared_hook).to receive(:feature_allowed?).and_return(true)
        allow(processor_service).to receive(:handle_contact).with(contact)

        # Mock the with_lock method directly on the job instance
        job_instance = described_class.new
        allow(job_instance).to receive(:with_lock).and_yield
        allow(described_class).to receive(:new).and_return(job_instance)

        expect(job_instance).to receive(:with_lock).with(
          format(Redis::Alfred::CRM_PROCESS_MUTEX, hook_id: leadsquared_hook.id)
        )

        job_instance.perform(leadsquared_hook, event_name, event_data)
      end

      it 'does not process when feature is not allowed' do
        allow(leadsquared_hook).to receive(:disabled?).and_return(false)
        allow(leadsquared_hook).to receive(:feature_allowed?).and_return(false)

        job_instance = described_class.new
        allow(job_instance).to receive(:with_lock)

        expect(job_instance).not_to receive(:with_lock)
        expect(processor_service).not_to receive(:handle_contact)

        job_instance.perform(leadsquared_hook, event_name, event_data)
      end
    end

    context 'when processing conversation.created event' do
      let(:event_name) { 'conversation.created' }
      let(:event_data) { { conversation: conversation } }

      it 'uses a lock when processing' do
        allow(leadsquared_hook).to receive(:disabled?).and_return(false)
        allow(leadsquared_hook).to receive(:feature_allowed?).and_return(true)
        allow(processor_service).to receive(:handle_conversation_created).with(conversation)

        job_instance = described_class.new
        allow(job_instance).to receive(:with_lock).and_yield
        allow(described_class).to receive(:new).and_return(job_instance)

        expect(job_instance).to receive(:with_lock).with(
          format(Redis::Alfred::CRM_PROCESS_MUTEX, hook_id: leadsquared_hook.id)
        )

        job_instance.perform(leadsquared_hook, event_name, event_data)
      end
    end

    context 'when processing conversation.resolved event' do
      let(:event_name) { 'conversation.resolved' }
      let(:event_data) { { conversation: conversation } }

      it 'uses a lock when processing' do
        allow(leadsquared_hook).to receive(:disabled?).and_return(false)
        allow(leadsquared_hook).to receive(:feature_allowed?).and_return(true)
        allow(processor_service).to receive(:handle_conversation_resolved).with(conversation)

        job_instance = described_class.new
        allow(job_instance).to receive(:with_lock).and_yield
        allow(described_class).to receive(:new).and_return(job_instance)

        expect(job_instance).to receive(:with_lock).with(
          format(Redis::Alfred::CRM_PROCESS_MUTEX, hook_id: leadsquared_hook.id)
        )

        job_instance.perform(leadsquared_hook, event_name, event_data)
      end
    end

    context 'when processing invalid event' do
      let(:event_name) { 'invalid.event' }
      let(:event_data) { { contact: contact } }

      it 'does not process for invalid event names' do
        allow(leadsquared_hook).to receive(:disabled?).and_return(false)
        allow(leadsquared_hook).to receive(:feature_allowed?).and_return(true)

        job_instance = described_class.new
        allow(job_instance).to receive(:with_lock)

        expect(job_instance).not_to receive(:with_lock)
        expect(processor_service).not_to receive(:handle_contact)

        job_instance.perform(leadsquared_hook, event_name, event_data)
      end
    end
  end

  context 'with a twenty hook' do
    let(:contact) { create(:contact, account: account, email: 'anna@acme.com') }
    let(:note) { create(:note, account: account, contact: contact) }
    let(:twenty_hook) do
      stub_request(:post, 'https://crm.example.com/graphql')
        .to_return(status: 200, body: { data: { workspaceMembers: { totalCount: 1 } } }.to_json, headers: { 'Content-Type' => 'application/json' })
      create(:integrations_hook, :twenty, account: account)
    end
    let(:processor) { instance_double(Crm::Twenty::ProcessorService, contact_id_for: contact.id) }

    before { allow(Crm::Twenty::ProcessorService).to receive(:new).with(twenty_hook).and_return(processor) }

    it 'processes the event under a per-contact lock' do
      job_instance = described_class.new
      allow(job_instance).to receive(:with_lock).with("CRM_PROCESS_MUTEX::#{twenty_hook.id}::#{contact.id}", 30.seconds).and_yield
      expect(processor).to receive(:process).with('note.created', { note: note })

      job_instance.perform(twenty_hook, 'note.created', { note: note })
    end

    # The generic rescue in #perform used to swallow these, so retry_on never ran.
    it 'lets a throttled request escape so the job is retried' do
      allow(processor).to receive(:process).and_raise(Crm::Twenty::Api::Client::RateLimitError, 'Limit reached')

      expect { described_class.new.perform(twenty_hook, 'note.created', { note: note }) }
        .to raise_error(Crm::Twenty::Api::Client::RateLimitError)
    end

    it 'lets a lock conflict escape so the job is retried' do
      job_instance = described_class.new
      allow(job_instance).to receive(:with_lock).and_raise(MutexApplicationJob::LockAcquisitionError)

      expect { job_instance.perform(twenty_hook, 'note.created', { note: note }) }
        .to raise_error(MutexApplicationJob::LockAcquisitionError)
    end

    it 'retries a throttled job a minute later' do
      allow(processor).to receive(:process).and_raise(Crm::Twenty::Api::Client::RateLimitError, 'Limit reached')

      expect { described_class.perform_now(twenty_hook, 'note.created', { note: note }) }
        .to have_enqueued_job(described_class).with(twenty_hook, 'note.created', { note: note })
    end

    it 'logs a throttled attempt to the CRM sync log' do
      allow(processor).to receive(:process).and_raise(Crm::Twenty::Api::Client::RateLimitError, 'Limit reached')

      expect { described_class.new.perform(twenty_hook, 'note.created', { note: note }) }.to raise_error(Crm::Twenty::Api::Client::RateLimitError)

      expect(CrmSyncEvent.last).to have_attributes(action: 'rate_limited', status: 'failure', contact_id: contact.id, message: 'Limit reached')
    end

    it 'logs a failure to the CRM sync log and does not retry it' do
      allow(processor).to receive(:process).and_raise(Crm::Twenty::Api::Client::ApiError, 'Twenty API error: 500')

      expect { described_class.new.perform(twenty_hook, 'note.created', { note: note }) }.not_to raise_error

      expect(CrmSyncEvent.last).to have_attributes(action: 'failed', status: 'failure', contact_id: contact.id, message: 'Twenty API error: 500',
                                                   details: { 'event' => 'note.created', 'error_class' => 'Crm::Twenty::Api::Client::ApiError' })
    end

    it 'does not log a lock conflict, which is only retried' do
      job_instance = described_class.new
      allow(job_instance).to receive(:with_lock).and_raise(MutexApplicationJob::LockAcquisitionError)

      expect { job_instance.perform(twenty_hook, 'note.created', { note: note }) }.to raise_error(MutexApplicationJob::LockAcquisitionError)

      expect(CrmSyncEvent.count).to eq(0)
    end
  end
end
