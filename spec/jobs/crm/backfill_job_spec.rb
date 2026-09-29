require 'rails_helper'

RSpec.describe Crm::BackfillJob do
  let(:account) { create(:account) }
  let(:hook) { create(:integrations_hook, :twenty, account: account, settings: { 'api_url' => 'https://crm.example.com', 'api_key' => 'key' }) }
  let(:progress) { Crm::BackfillProgress.new(hook) }
  let(:job) { described_class.new }
  let!(:unlinked) { create(:contact, account: account, name: 'Anna Tsai', email: 'anna@acme.com') }
  let!(:linked) do
    create(:contact, account: account, name: 'Brandon Lu', email: 'brandon@acme.com',
                     additional_attributes: { 'external' => { 'twenty_id' => 'person-2' } })
  end
  let!(:unknown) { create(:contact, account: account, name: 'Nobody', email: 'nobody@example.com') }
  let(:anna) do
    { 'id' => 'person-1', 'name' => { 'firstName' => 'Anna', 'lastName' => 'Tsai' }, 'emails' => { 'primaryEmail' => 'anna@acme.com' },
      'phones' => {}, 'jobTitle' => 'CTO', 'linkedinLink' => {}, 'company' => nil }
  end
  let(:brandon) do
    { 'id' => 'person-2', 'name' => { 'firstName' => 'Brandon', 'lastName' => 'Lu' }, 'emails' => { 'primaryEmail' => 'brandon@acme.com' },
      'phones' => {}, 'jobTitle' => 'Sales lead', 'linkedinLink' => {}, 'company' => nil,
      'pointOfContactForOpportunities' => { 'edges' => [] }, 'noteTargets' => { 'totalCount' => 0, 'edges' => [] } }
  end

  def stub_twenty(operation, &)
    stub_request(:post, 'https://crm.example.com/graphql')
      .with { |request| JSON.parse(request.body)['query'].include?(operation) }
      .to_return do |request|
        { status: 200, body: { data: yield(JSON.parse(request.body)['variables']) }.to_json, headers: { 'Content-Type' => 'application/json' } }
      end
  end

  before do
    stub_twenty('query Verify') { { 'workspaceMembers' => { 'totalCount' => 1 } } }
    stub_twenty('query FindPeople') do |variables|
      emails = variables.dig('filter', 'or').filter_map { |condition| condition.dig('emails', 'primaryEmail', 'eq') }
      { 'people' => { 'edges' => emails.include?('anna@acme.com') ? [{ 'node' => anna }] : [] } }
    end
    stub_twenty('query PersonCard') do |variables|
      { 'person' => variables['id'] == 'person-1' ? anna.merge(brandon.slice('pointOfContactForOpportunities', 'noteTargets')) : brandon }
    end
    allow(job).to receive(:sleep)
    progress.start!(3)
  end

  it 'links unlinked contacts, refreshes linked ones and never creates anyone' do
    job.perform(hook)

    expect(unlinked.reload.additional_attributes.dig('external', 'twenty_id')).to eq('person-1')
    expect(unlinked.custom_attributes).to include('crm_status' => 'Linked', 'crm_job_title' => 'CTO')
    expect(linked.reload.custom_attributes).to include('crm_status' => 'Linked', 'crm_job_title' => 'Sales lead')
    expect(unknown.reload.custom_attributes).to include('crm_status' => 'Not linked')
    create_person = a_request(:post, 'https://crm.example.com/graphql').with { |request| request.body.include?('mutation CreatePerson') }
    expect(create_person).not_to have_been_made
  end

  it 'reports its progress and logs its start and finish' do
    job.perform(hook)

    expect(Crm::BackfillProgress.new(hook).status).to include(
      'state' => 'finished', 'total' => 3, 'processed' => 3, 'linked' => 1, 'refreshed' => 1, 'no_match' => 1, 'ambiguous' => 0, 'errors' => 0
    )
    expect(Crm::BackfillProgress.new(hook).status['finished_at']).to be_present
    expect(progress).not_to be_running
    expect(CrmSyncEvent.where(action: %w[backfill_started backfill_finished]).order(:id).pluck(:action, :details)).to eq(
      [['backfill_started', { 'total' => 3 }],
       ['backfill_finished', { 'linked' => 1, 'refreshed' => 1, 'ambiguous' => 0, 'no_match' => 1, 'errors' => 0 }]]
    )
    expect(CrmSyncEvent.where(action: 'attributes_refreshed', contact_id: linked.id)).to exist
  end

  it 'waits out a rate limit and retries the contact' do
    calls = 0
    stub_request(:post, 'https://crm.example.com/graphql').with { |request| request.body.include?('query FindPeople') }.to_return do |request|
      calls += 1
      data = if calls == 1
               { errors: [{ message: 'Limit reached' }] }
             else
               conditions = JSON.parse(request.body).dig('variables', 'filter', 'or')
               emails = conditions.filter_map { |condition| condition.dig('emails', 'primaryEmail', 'eq') }
               { data: { 'people' => { 'edges' => emails.include?('anna@acme.com') ? [{ 'node' => anna }] : [] } } }
             end
      { status: 200, body: data.to_json, headers: { 'Content-Type' => 'application/json' } }
    end

    job.perform(hook)

    expect(job).to have_received(:sleep).with(60.seconds)
    expect(Crm::BackfillProgress.new(hook).status).to include('linked' => 1, 'errors' => 0)
    expect(CrmSyncEvent.where(action: 'rate_limited').count).to eq(1)
  end

  it 'counts and logs a contact that fails, and goes on' do
    stub_request(:post, 'https://crm.example.com/graphql').with { |request| request.body.include?('query FindPeople') }.to_return(status: 500)

    job.perform(hook)

    expect(Crm::BackfillProgress.new(hook).status).to include('processed' => 3, 'refreshed' => 1, 'errors' => 2)
    expect(CrmSyncEvent.where(action: 'failed', status: 'failure').pluck(:details))
      .to all(include('error_class' => 'Crm::Twenty::Api::Client::ApiError'))
  end

  it 'allows one run per hook at a time' do
    expect(progress.start!(3)).to be(false)

    job.perform(hook)

    expect(progress.start!(3)).to be(true)
  end

  it 'stops when the hook is turned off' do
    hook.update_columns(status: 'disabled') # rubocop:disable Rails/SkipsModelValidations

    job.perform(hook)

    expect(Crm::BackfillProgress.new(hook).status).to include('state' => 'finished', 'processed' => 0)
  end
end
