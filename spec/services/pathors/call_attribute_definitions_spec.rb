require 'rails_helper'

RSpec.describe Pathors::CallAttributeDefinitions do
  let(:account) { create(:account) }

  describe '.ensure!' do
    it 'defines the three conversation attributes once' do
      2.times { described_class.ensure!(account) }

      definitions = account.custom_attribute_definitions.conversation_attribute.index_by(&:attribute_key)
      expect(definitions.keys).to contain_exactly('pathors_call_from', 'pathors_call_outcome', 'pathors_takeover_requested')
      expect(definitions['pathors_call_from']).to have_attributes(attribute_display_name: '來電號碼', attribute_display_type: 'text')
      expect(definitions['pathors_call_outcome']).to have_attributes(attribute_display_type: 'list',
                                                                     attribute_values: Pathors::CallLifecycleService::OUTCOMES)
      expect(definitions['pathors_takeover_requested'].attribute_display_type).to eq('checkbox')
    end

    it 'keeps a definition an admin already made with the same key' do
      create(:custom_attribute_definition, account: account, attribute_key: 'pathors_call_from', attribute_model: 'conversation_attribute',
                                           attribute_display_name: 'Caller', attribute_display_type: 'link')

      described_class.ensure!(account)

      expect(account.custom_attribute_definitions.find_by(attribute_key: 'pathors_call_from'))
        .to have_attributes(attribute_display_name: 'Caller', attribute_display_type: 'link')
    end
  end

  describe '.ensure_once!' do
    it 'never raises into the call create it runs inside' do
      allow(described_class).to receive(:ensure!).and_raise(ActiveRecord::RecordInvalid)

      expect(described_class.ensure_once!(account)).to be(false)
    end
  end
end
