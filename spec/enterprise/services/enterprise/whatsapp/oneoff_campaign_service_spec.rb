require 'rails_helper'

RSpec.describe Enterprise::Whatsapp::OneoffCampaignService do
  let(:account) { create(:account) }
  let(:whatsapp_channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
  end
  let(:whatsapp_inbox) { whatsapp_channel.inbox }
  let(:label) { create(:label, account: account) }
  let(:template_params) do
    {
      'name' => 'ticket_status_updated',
      'namespace' => '23423423_2342423_324234234_2343224',
      'category' => 'UTILITY',
      'language' => 'en',
      'processed_params' => { 'body' => { 'name' => 'John', 'ticket_id' => '2332' } }
    }
  end
  let(:campaign) do
    create(
      :campaign,
      inbox: whatsapp_inbox,
      account: account,
      audience: [{ type: 'Label', id: label.id }],
      template_params: template_params
    )
  end

  before do
    account.enable_features!(:whatsapp_campaign)
    allow_any_instance_of(Whatsapp::OneoffCampaignService).to receive(:channel).and_return(whatsapp_channel) # rubocop:disable RSpec/AnyInstance
  end

  it 'leaves blocked contacts out of the campaign recipients' do
    blocked_contact, unblocked_contact = create_list(:contact, 2, :with_phone_number, account: account)
    blocked_contact.update!(blocked: true)
    blocked_contact.update_labels([label.title])
    unblocked_contact.update_labels([label.title])

    expect(whatsapp_channel).not_to receive(:send_template).with(blocked_contact.phone_number, anything, nil)
    expect(whatsapp_channel).to receive(:send_template).with(unblocked_contact.phone_number, anything, nil).once

    Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

    expect(CampaignRecipient.where(campaign: campaign).pluck(:contact_id)).to eq([unblocked_contact.id])
  end

  it 'marks contacts without phone or BSUID as skipped' do
    contact = create(:contact, account: account, phone_number: nil)
    contact.update_labels([label.title])

    expect(whatsapp_channel).not_to receive(:send_template)

    Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

    expect(CampaignRecipient.find_by!(campaign: campaign, contact: contact)).to be_skipped
  end

  it 'marks phone-less contacts with multiple WhatsApp identities as skipped' do
    contact = create(:contact, account: account, phone_number: nil)
    contact.update_labels([label.title])
    create(:contact_inbox, contact: contact, inbox: whatsapp_inbox, source_id: 'IN.2081978709342942')
    create(:contact_inbox, contact: contact, inbox: whatsapp_inbox, source_id: 'IN.2081978709342943')

    expect(whatsapp_channel).not_to receive(:send_template)

    Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

    expect(CampaignRecipient.find_by!(campaign: campaign, contact: contact)).to be_skipped
  end

  it 'marks blocked BSUID-only authentication-template recipients as skipped' do
    contact = create(:contact, account: account, phone_number: nil)
    contact.update_labels([label.title])
    create(:contact_inbox, contact: contact, inbox: whatsapp_inbox, source_id: 'IN.2081978709342942')
    whatsapp_channel.update!(
      message_templates: [
        {
          'name' => 'ticket_status_updated',
          'language' => 'en',
          'category' => 'AUTHENTICATION'
        }
      ]
    )

    expect(whatsapp_channel).not_to receive(:send_template)

    Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

    expect(CampaignRecipient.find_by!(campaign: campaign, contact: contact)).to be_skipped
  end
end
