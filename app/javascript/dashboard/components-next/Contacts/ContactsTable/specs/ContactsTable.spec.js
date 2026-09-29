import { flushPromises, mount } from '@vue/test-utils';
import { ref } from 'vue';
import { getUnixTime, subDays } from 'date-fns';
import ContactsTable from '../ContactsTable.vue';

const push = vi.fn();
vi.mock('vue-router', () => ({
  useRoute: () => ({ name: 'contacts_dashboard_index', params: {}, query: {} }),
  useRouter: () => ({ push }),
}));

const getters = {
  'labels/getLabels': ref([]),
  'attributes/getContactAttributes': ref([]),
};
vi.mock('dashboard/composables/store', () => ({
  // Popover also reads accounts/isRTL.
  useMapGetter: name => getters[name] ?? ref(false),
}));

const uiSettings = ref({});
const updateUISettings = vi.fn();
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({ uiSettings, updateUISettings }),
}));

const TABLE = 'CONTACTS_LAYOUT.TABLE';
const daysAgo = days => getUnixTime(subDays(new Date(), days));

const crmStatus = values => ({
  attributeKey: 'crm_status',
  attributeDisplayName: 'CRM status',
  attributeDisplayType: 'list',
  attributeValues: values,
});
const website = {
  attributeKey: 'website',
  attributeDisplayName: 'Website',
  attributeDisplayType: 'link',
};
const renewal = {
  attributeKey: 'renewal_on',
  attributeDisplayName: 'Renewal',
  attributeDisplayType: 'date',
};

const contacts = [
  {
    id: 1,
    name: 'Rea Sagang',
    email: 'rea@acme.com',
    phoneNumber: '+886912345678',
    additionalAttributes: { companyName: 'Acme' },
    labels: ['vip', 'lead', 'newsletter'],
    sourceInbox: {
      id: 5,
      name: 'Contact Pathors',
      channelType: 'Channel::Email',
    },
    lastActivityAt: daysAgo(2),
    customAttributes: {
      crm_status: '已連結',
      crm_provider: 'Twenty',
      crm_stage: 'Proposal',
      crm_opportunity: 'Acme renewal',
      crm_owner: 'Jack',
      crm_url: 'https://crm.example.com/people/1',
      crm_job_title: 'CTO',
      website: 'https://acme.com',
    },
  },
  {
    id: 2,
    name: '+886 912 000 111',
    phoneNumber: '+886912000111',
    sourceInbox: { id: 7, name: 'Hotline', channelType: 'Channel::Voice' },
    lastActivityAt: daysAgo(60),
    customAttributes: { crm_status: '需要處理' },
  },
  {
    id: 3,
    name: 'mei',
    email: 'mei@example.com',
    customAttributes: { crm_status: '未連結' },
  },
];

describe('ContactsTable', () => {
  let wrapper;

  const mountTable = props => {
    wrapper = mount(ContactsTable, {
      props: { contacts, ...props },
      global: { renderStubDefaultSlot: true, stubs: { teleport: true } },
      attachTo: document.body,
    });
    return wrapper;
  };

  const rows = () => wrapper.findAll('[data-test="contact-row"]');
  const headers = () => wrapper.findAll('th').map(th => th.text());

  beforeEach(() => {
    getters['labels/getLabels'].value = [
      { title: 'vip', color: '#ff0000' },
      { title: 'lead', color: '#00ff00' },
    ];
    getters['attributes/getContactAttributes'].value = [
      crmStatus(['已連結', '需要處理', '未連結']),
      website,
      renewal,
    ];
    uiSettings.value = {};
  });

  afterEach(() => {
    wrapper?.unmount();
    document.body.innerHTML = '';
  });

  it('renders one compact row per contact with every column', () => {
    mountTable();

    expect(headers()).toEqual([
      '',
      `${TABLE}.COLUMNS.NAME`,
      `${TABLE}.COLUMNS.COMPANY`,
      `${TABLE}.COLUMNS.CONTACT`,
      `${TABLE}.COLUMNS.SOURCE`,
      `${TABLE}.COLUMNS.LABELS`,
      `${TABLE}.COLUMNS.CRM`,
      `${TABLE}.COLUMNS.LAST_ACTIVITY`,
      `${TABLE}.COLUMNS_MENU.LABEL`,
    ]);

    const first = rows()[0];
    const text = first.text();
    expect(first.find('[data-test="contact-name"]').text()).toBe('Rea Sagang');
    expect(text).toContain('Acme');
    expect(text).toContain(`${TABLE}.JOB_TITLE`);
    expect(text).toContain('rea@acme.com');
    expect(text).not.toContain('+886912345678');
    expect(text).toContain('Contact Pathors');
    expect(first.find('[data-test="source-icon"]').classes()).toContain(
      'i-lucide-mail'
    );
    // Two label chips, then the rest as a count.
    expect(text).toContain('vip');
    expect(text).toContain('lead');
    expect(text).not.toContain('newsletter');
    expect(text).toContain(`${TABLE}.MORE_LABELS`);
    expect(text).toContain('Proposal');

    expect(rows()[1].find('[data-test="source-icon"]').classes()).toContain(
      'i-lucide-phone'
    );
    expect(rows()[1].text()).toContain('+886912000111');
  });

  it('fades last activity older than a week', () => {
    mountTable();
    const activity = index =>
      rows()[index].find('[data-test="last-activity"]').classes();

    expect(activity(0)).toContain('text-n-slate-12');
    expect(activity(1)).toContain('text-n-slate-10');
  });

  it('mutes names that only repeat the phone number or the email', () => {
    mountTable();
    const isMuted = index =>
      rows()
        [index].find('[data-test="contact-name"]')
        .classes()
        .includes('text-n-slate-10');

    expect(isMuted(0)).toBe(false);
    expect(isMuted(1)).toBe(true);
    expect(isMuted(2)).toBe(true);
  });

  it('maps crm_status to a state by its position in the definition', () => {
    getters['attributes/getContactAttributes'].value = [
      crmStatus(['Linked', 'Needs attention', 'Not linked']),
    ];
    mountTable({
      contacts: [
        { id: 1, name: 'A', customAttributes: { crm_status: 'Linked' } },
        {
          id: 2,
          name: 'B',
          customAttributes: { crm_status: 'Needs attention' },
        },
        { id: 3, name: 'C', customAttributes: { crm_status: 'Not linked' } },
        // A label from another locale is not in this account's list.
        { id: 4, name: 'D', customAttributes: { crm_status: '已連結' } },
      ],
    });

    const states = rows().map(row => {
      const dot = row.find('[data-test="crm-status-dot"]');
      return dot.exists() ? dot.attributes('data-status') : null;
    });
    expect(states).toEqual(['linked', 'needs_attention', null, null]);
    expect(rows()[2].text()).toContain(`${TABLE}.EMPTY_CELL`);
  });

  it('hides the CRM column while the account has no crm_status attribute', () => {
    getters['attributes/getContactAttributes'].value = [website];
    mountTable();

    expect(headers()).not.toContain(`${TABLE}.COLUMNS.CRM`);
    expect(wrapper.find('[data-test="crm-cell"]').exists()).toBe(false);
  });

  it('opens the contact when a row is clicked', async () => {
    mountTable();
    await rows()[1].trigger('click');

    expect(push).toHaveBeenCalledWith({
      name: 'contacts_edit',
      params: { contactId: 2 },
      query: {},
    });
  });

  it('opens the CRM record from the CRM cell without opening the contact', async () => {
    mountTable();
    const link = rows()[0].find('a[data-test="crm-cell"]');

    expect(link.attributes('href')).toBe('https://crm.example.com/people/1');
    expect(link.attributes('target')).toBe('_blank');
    await link.trigger('click');
    expect(push).not.toHaveBeenCalled();
  });

  it('selects a row from its checkbox without opening the contact', async () => {
    mountTable();
    await rows()[0].find('input[type="checkbox"]').trigger('click');

    expect(wrapper.emitted('toggleContact')).toEqual([
      [{ id: 1, value: true }],
    ]);
    expect(push).not.toHaveBeenCalled();
  });

  it('sorts from a header through the shared sort state', async () => {
    mountTable({ activeSort: 'name', activeOrdering: '' });
    const button = text =>
      wrapper.findAll('th button').find(item => item.text() === text);

    await button(`${TABLE}.COLUMNS.NAME`).trigger('click');
    await button(`${TABLE}.COLUMNS.LAST_ACTIVITY`).trigger('click');

    expect(wrapper.emitted('update:sort')).toEqual([
      [{ sort: 'name', order: '-' }],
      [{ sort: 'last_activity_at', order: '' }],
    ]);
  });

  it('shows the extra columns saved in the UI settings', () => {
    uiSettings.value = { contacts_table_extra_columns: ['website', 'gone'] };
    mountTable();

    expect(headers()).toContain('Website');
    const link = rows()[0].find('a[href="https://acme.com"]');
    expect(link.attributes('target')).toBe('_blank');
  });

  it('saves a column picked in the columns menu to the UI settings', async () => {
    uiSettings.value = { contacts_table_extra_columns: ['website'] };
    mountTable();

    await wrapper
      .findAll('th button')
      .find(item => item.text() === `${TABLE}.COLUMNS_MENU.LABEL`)
      .trigger('click');
    await flushPromises();

    const option = wrapper
      .findAll('label')
      .find(label => label.text() === 'Renewal');
    await option.find('input').setValue(true);

    expect(updateUISettings).toHaveBeenCalledWith({
      contacts_table_extra_columns: ['website', 'renewal_on'],
    });
  });
});
