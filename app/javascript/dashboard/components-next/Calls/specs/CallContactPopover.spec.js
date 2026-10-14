import { flushPromises, mount } from '@vue/test-utils';
import { ref } from 'vue';
import { withFullI18n } from 'test-i18n';
import CallsAPI from 'dashboard/api/calls';
import ContactAPI from 'dashboard/api/contacts';
import CallContactPopover from '../CallContactPopover.vue';

withFullI18n('zh_TW');

vi.mock('dashboard/api/calls', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/contacts', () => ({
  default: { getContactLabels: vi.fn() },
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ref(false),
}));

const CALL = {
  id: 77,
  contact: { id: 5, name: '林先生', phoneNumber: '+886933963188' },
};

const mountPopover = (call = CALL) =>
  mount(CallContactPopover, {
    props: { call, accountId: 1, title: '林先生' },
    global: {
      renderStubDefaultSlot: true,
      stubs: { teleport: true, RouterLink: { template: '<a><slot /></a>' } },
    },
    attachTo: document.body,
  });

const find = (wrapper, id) => wrapper.find(`[data-test-id="${id}"]`);

const open = async wrapper => {
  await find(wrapper, 'call-contact-trigger').trigger('click');
  await flushPromises();
};

describe('CallContactPopover', () => {
  let wrapper;

  beforeEach(() => {
    ContactAPI.getContactLabels.mockResolvedValue({
      data: { payload: ['VIP', '回撥'] },
    });
    CallsAPI.get.mockResolvedValue({
      data: {
        payload: [
          { id: 77, started_at: 1_760_000_000, outcome: 'ai_done' },
          { id: 55, started_at: 1_759_900_000, outcome: 'transfer_failed' },
        ],
      },
    });
  });

  afterEach(() => {
    wrapper?.unmount();
    document.body.innerHTML = '';
  });

  it("shows the caller's labels and earlier calls, without the open one", async () => {
    wrapper = mountPopover();
    await open(wrapper);

    expect(ContactAPI.getContactLabels).toHaveBeenCalledWith(5);
    expect(CallsAPI.get).toHaveBeenCalledWith({ contact_id: 5 });
    const card = find(wrapper, 'call-contact-card');
    expect(card.text()).toContain('+886933963188');
    expect(card.text()).toContain('VIP');
    const earlier = wrapper.findAll(
      '[data-test-id="call-contact-earlier-call"]'
    );
    expect(earlier).toHaveLength(1);
    expect(find(wrapper, 'call-contact-open').exists()).toBe(true);
  });

  it('asks the sheet to open an earlier call', async () => {
    wrapper = mountPopover();
    await open(wrapper);

    await find(wrapper, 'call-contact-earlier-call').trigger('click');

    expect(wrapper.emitted('openCall')).toEqual([[55]]);
  });

  it('works from a live record, which flattens the contact', async () => {
    wrapper = mountPopover({
      id: 77,
      contactId: 5,
      contactName: '林先生',
      contactPhoneNumber: '+886933963188',
    });
    await open(wrapper);

    expect(CallsAPI.get).toHaveBeenCalledWith({ contact_id: 5 });
  });

  it('is a plain title for a call without a contact', () => {
    wrapper = mountPopover({ id: 77, contact: null });

    expect(find(wrapper, 'call-contact-trigger').exists()).toBe(false);
    expect(find(wrapper, 'call-title').text()).toBe('林先生');
  });
});
