require 'rails_helper'

RSpec.describe Crm::Twenty::Conflicts do
  let(:account) { create(:account) }
  let(:contact) do
    create(:contact, account: account, name: 'Anna Tsai', email: 'anna@acme.com', phone_number: '+886912345678',
                     additional_attributes: { 'company_name' => 'Acme' })
  end
  let(:person) do
    {
      'id' => 'person-1',
      'name' => { 'firstName' => 'Anna', 'lastName' => 'Tsai' },
      'emails' => { 'primaryEmail' => 'anna@acme.com', 'additionalEmails' => [] },
      'phones' => { 'primaryPhoneNumber' => '912345678', 'primaryPhoneCallingCode' => '+886', 'additionalPhones' => [] },
      'company' => { 'id' => 'company-1', 'name' => 'ACME' }
    }
  end
  let(:conflicts) { described_class.new(contact) }

  it 'finds nothing when the two records agree, whatever the spelling' do
    expect(conflicts.for_person(person)).to eq([])
  end

  it 'raises a field conflict for each value the two sides hold differently' do
    person['emails']['primaryEmail'] = 'a.tsai@acme.com'
    person['phones']['primaryPhoneNumber'] = '911111111'

    expect(conflicts.for_person(person)).to contain_exactly(
      { 'type' => 'field', 'field' => 'email', 'inbox' => 'anna@acme.com', 'twenty' => 'a.tsai@acme.com' },
      { 'type' => 'field', 'field' => 'phone', 'inbox' => '+886912345678', 'twenty' => '+886911111111' }
    )
  end

  it 'accepts a value Twenty holds as an additional email or phone' do
    person['emails'] = { 'primaryEmail' => 'a.tsai@acme.com', 'additionalEmails' => ['Anna@acme.com'] }
    person['phones'] = { 'primaryPhoneNumber' => '911111111', 'primaryPhoneCallingCode' => '+886',
                         'additionalPhones' => [{ 'number' => '0912345678' }] }

    expect(conflicts.for_person(person)).to eq([])
  end

  it 'does not treat a shortened name or the same name in another script as a conflict' do
    person['name'] = { 'firstName' => 'Anna', 'lastName' => '' }
    expect(conflicts.for_person(person)).to eq([])

    person['name'] = { 'firstName' => '安娜', 'lastName' => '蔡' }
    expect(conflicts.for_person(person)).to eq([])

    person['name'] = { 'firstName' => 'Anne', 'lastName' => 'Chen' }
    expect(conflicts.for_person(person).pluck('field')).to eq(['name'])
  end

  it 'flags another contact linked to the same person' do
    other = create(:contact, account: account, name: 'Anna (phone)', additional_attributes: { 'external' => { 'twenty_id' => 'person-1' } })

    expect(conflicts.for_person(person)).to eq(
      [{ 'type' => 'duplicate_contact', 'contact' => { 'id' => other.id, 'name' => 'Anna (phone)', 'email' => nil, 'phone_number' => nil } }]
    )
  end

  describe 'LINE ids' do
    let(:line_user_id) { "U#{'4af49806' * 4}" }

    before do
      contact.update!(additional_attributes: contact.additional_attributes.merge('social_profiles' => { 'line' => 'Anna_Tsai' },
                                                                                 'social_line_user_id' => line_user_id))
    end

    it 'agrees on a LINE ID written in another case' do
      person.merge!('lineId' => 'anna_tsai', 'lineUserId' => line_user_id)

      expect(conflicts.for_person(person)).to eq([])
    end

    it 'raises a field conflict for each LINE id the two sides hold differently' do
      person.merge!('lineId' => 'annatsai', 'lineUserId' => "U#{'0' * 32}")

      expect(conflicts.for_person(person)).to contain_exactly(
        { 'type' => 'field', 'field' => 'line_id', 'inbox' => 'Anna_Tsai', 'twenty' => 'annatsai' },
        { 'type' => 'field', 'field' => 'line_user_id', 'inbox' => line_user_id, 'twenty' => "U#{'0' * 32}" }
      )
    end

    it 'flags another contact holding the person\'s LINE User ID or LINE ID' do
      by_user_id = create(:contact, account: account, name: 'Anna (LINE)', additional_attributes: { 'social_line_user_id' => "U#{'1' * 32}" })
      by_line_id = create(:contact, account: account, name: 'Anna (friend)', additional_attributes: { 'social_profiles' => { 'line' => 'Anna.T' } })
      person.merge!('lineUserId' => "U#{'1' * 32}", 'lineId' => 'anna.t')

      duplicates = conflicts.for_person(person).select { |conflict| conflict['type'] == 'duplicate_contact' }
      expect(duplicates.map { |conflict| conflict.dig('contact', 'id') }).to eq([by_user_id.id, by_line_id.id])
    end
  end

  it 'stops raising a dismissed conflict until one of the values changes' do
    person['emails']['primaryEmail'] = 'a.tsai@acme.com'
    conflict = conflicts.for_person(person).first
    contact.update!(additional_attributes: contact.additional_attributes.merge(
      'external' => { described_class::DISMISSED_KEY => [described_class.fingerprint(conflict)] }
    ))

    expect(described_class.new(contact).for_person(person)).to eq([])
    person['emails']['primaryEmail'] = 'tsai@acme.com'
    expect(described_class.new(contact).for_person(person).pluck('twenty')).to eq(['tsai@acme.com'])
  end
end
