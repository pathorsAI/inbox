require 'rails_helper'

RSpec.describe Crm::Twenty::PersonMapper do
  let(:account) { create(:account) }
  let(:contact) do
    create(:contact, account: account, name: 'Anna Tsai', email: 'anna@acme.com', phone_number: '+886912345678',
                     additional_attributes: { 'city' => 'Taipei', 'social_profiles' => { 'linkedin' => 'in/anna' } })
  end
  let(:mapper) { described_class.new(contact) }
  let(:person) do
    {
      'id' => 'person-1',
      'name' => { 'firstName' => '', 'lastName' => '' },
      'emails' => { 'primaryEmail' => '' },
      'phones' => { 'primaryPhoneNumber' => '', 'primaryPhoneCallingCode' => '' },
      'city' => '',
      'linkedinLink' => { 'primaryLinkUrl' => '' },
      'company' => nil
    }
  end

  describe '.phone' do
    it 'splits a Taiwanese mobile the way Twenty stores it and lists every older spelling' do
      expect(described_class.phone('+886912345678')).to eq(
        number: '912345678', country: 'TW', calling_code: '+886',
        variants: %w[912345678 0912345678 886912345678 +886912345678]
      )
    end

    it 'has no trunk-prefix variant where the country has none' do
      expect(described_class.phone('+85291234567')[:variants]).to eq(%w[91234567 85291234567 +85291234567])
    end
  end

  describe '.full_name' do
    it 'joins a Chinese name family name first, without a space' do
      expect(described_class.full_name('name' => { 'firstName' => '宇傑', 'lastName' => '鄭' })).to eq('鄭宇傑')
    end

    it 'joins other names first name first' do
      expect(described_class.full_name('name' => { 'firstName' => 'Anna', 'lastName' => 'Tsai' })).to eq('Anna Tsai')
    end
  end

  describe '.placeholder_name?' do
    it 'treats blanks, phone numbers and the email address as placeholders' do
      expect(described_class.placeholder_name?('')).to be(true)
      expect(described_class.placeholder_name?('0912-345-678')).to be(true)
      expect(described_class.placeholder_name?('anna', 'anna@acme.com')).to be(true)
      expect(described_class.placeholder_name?('Anna Tsai', 'anna@acme.com')).to be(false)
    end
  end

  describe '#create_attributes' do
    it 'maps the contact onto Twenty person fields' do
      expect(mapper.create_attributes).to eq(
        name: { firstName: 'Anna Tsai', lastName: '' },
        emails: { primaryEmail: 'anna@acme.com' },
        phones: { primaryPhoneNumber: '912345678', primaryPhoneCountryCode: 'TW', primaryPhoneCallingCode: '+886' },
        city: 'Taipei',
        linkedinLink: { primaryLinkUrl: 'https://www.linkedin.com/in/anna' }
      )
    end
  end

  describe '#person_updates' do
    it 'fills every blank on the person' do
      expect(mapper.person_updates(person).keys).to contain_exactly(:name, :emails, :phones, :city, :linkedinLink)
    end

    it 'leaves what Twenty already has alone' do
      person.merge!('name' => { 'firstName' => 'Anna', 'lastName' => 'T.' }, 'emails' => { 'primaryEmail' => 'a.tsai@acme.com' },
                    'city' => 'Hsinchu')

      expect(mapper.person_updates(person).keys).to contain_exactly(:phones, :linkedinLink)
    end

    it 'replaces a Twenty name that is only a phone number' do
      person['name'] = { 'firstName' => '0912345678', 'lastName' => '' }

      expect(mapper.person_updates(person)[:name]).to eq(firstName: 'Anna Tsai', lastName: '')
    end
  end

  describe '#contact_updates' do
    let(:contact) { create(:contact, account: account, name: '+886912345678', phone_number: '+886912345678') }

    before do
      person.merge!('name' => { 'firstName' => '宇傑', 'lastName' => '鄭' }, 'emails' => { 'primaryEmail' => 'Jack@Acme.com' },
                    'city' => 'Taipei', 'company' => { 'id' => 'company-1', 'name' => 'Acme' },
                    'linkedinLink' => { 'primaryLinkUrl' => 'https://www.linkedin.com/in/jack' })
    end

    it 'names the contact and fills its blanks from Twenty' do
      expect(mapper.contact_updates(person)).to eq(
        name: '鄭宇傑',
        email: 'jack@acme.com',
        additional_attributes: { 'company_name' => 'Acme', 'city' => 'Taipei', 'social_profiles' => { 'linkedin' => 'in/jack' } }
      )
    end

    it 'does not copy an email another contact already has' do
      create(:contact, account: account, email: 'jack@acme.com')

      expect(mapper.contact_updates(person)).not_to have_key(:email)
    end
  end
end
