require 'rails_helper'

RSpec.describe Crm::ContactAttributes do
  let(:account) { create(:account, locale: 'zh_TW') }
  let(:contact) { create(:contact, account: account, custom_attributes: { 'plan' => 'pro', 'vip' => false }) }
  let(:definitions) { account.custom_attribute_definitions.contact_attribute }

  describe '.ensure_definitions!' do
    it 'creates the eight CRM attributes in the account language, once' do
      described_class.ensure_definitions!(account)
      described_class.instance_variable_get(:@ensured).delete(account.id)
      described_class.ensure_definitions!(account)

      expect(definitions.pluck(:attribute_key)).to match_array(described_class::DEFINITIONS.keys)
      status = definitions.find_by(attribute_key: 'crm_status')
      expect(status.attribute_display_type).to eq('list')
      expect(status.attribute_values).to eq(%w[已連結 需要處理 未連結])
      expect(status.attribute_display_name).to eq('CRM 狀態')
      expect(status.attribute_description).to eq('由 CRM 同步')
      expect(definitions.find_by(attribute_key: 'crm_url').attribute_display_type).to eq('link')
      expect(definitions.find_by(attribute_key: 'crm_synced_at').attribute_display_type).to eq('date')
    end

    it 'names them in English for an English account' do
      account.update!(locale: 'en')

      described_class.ensure_definitions!(account)

      expect(definitions.find_by(attribute_key: 'crm_status').attribute_values).to eq(['Linked', 'Needs attention', 'Not linked'])
      expect(definitions.find_by(attribute_key: 'crm_stage').attribute_display_name).to eq('Opportunity stage')
    end

    it 'leaves a definition the account already has alone' do
      create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute', attribute_key: 'crm_owner',
                                           attribute_display_name: 'Account manager')

      described_class.ensure_definitions!(account)

      expect(definitions.where(attribute_key: 'crm_owner').pluck(:attribute_display_name)).to eq(['Account manager'])
      expect(definitions.count).to eq(8)
    end
  end

  describe '.write' do
    it 'stores the values under crm_* keys, the status as its label, next to the other attributes' do
      synced_at = Time.zone.parse('2026-09-30T10:42:00Z')

      changed = described_class.write(contact, provider: 'Twenty', status: :needs_attention, job_title: 'CTO', stage: '',
                                               url: 'https://crm.example.com/object/person/p1', synced_at: synced_at)

      expect(contact.reload.custom_attributes).to eq(
        'plan' => 'pro', 'vip' => false, 'crm_provider' => 'Twenty', 'crm_status' => '需要處理', 'crm_job_title' => 'CTO',
        'crm_url' => 'https://crm.example.com/object/person/p1', 'crm_synced_at' => '2026-09-30T10:42:00Z'
      )
      expect(changed).to contain_exactly('crm_provider', 'crm_status', 'crm_job_title', 'crm_url', 'crm_synced_at')
    end

    it 'removes blank values and leaves omitted ones' do
      described_class.write(contact, provider: 'Twenty', stage: 'Meeting', owner: 'Jack Cheng')

      described_class.write(contact, stage: nil)

      expect(contact.reload.custom_attributes).to include('crm_provider' => 'Twenty', 'crm_owner' => 'Jack Cheng')
      expect(contact.custom_attributes).not_to have_key('crm_stage')
    end

    it 'does not save when nothing changed' do
      described_class.write(contact, provider: 'Twenty', status: :linked)

      expect(contact).not_to receive(:save!)
      expect(described_class.write(contact, provider: 'Twenty', status: :linked)).to eq([])
    end

    it 'rejects keys it does not know' do
      expect { described_class.write(contact, company: 'Acme') }.to raise_error(ArgumentError)
    end

    it 'recreates the status definition when it was deleted' do
      described_class.ensure_definitions!(account)
      definitions.find_by(attribute_key: 'crm_status').destroy!

      described_class.write(contact, status: :linked)

      expect(contact.reload.custom_attributes['crm_status']).to eq('已連結')
    end
  end

  describe '.clear' do
    it 'keeps only the provider and the status' do
      described_class.write(contact, provider: 'Twenty', status: :linked, job_title: 'CTO', stage: 'Meeting', opportunity: 'Voice',
                                     owner: 'Jack', url: 'https://x.y', synced_at: Time.current)

      described_class.clear(contact, provider: 'Twenty')

      expect(contact.reload.custom_attributes).to eq('plan' => 'pro', 'vip' => false, 'crm_provider' => 'Twenty', 'crm_status' => '未連結')
    end
  end
end
