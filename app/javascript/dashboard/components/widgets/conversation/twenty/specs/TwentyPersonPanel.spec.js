import { flushPromises, mount, RouterLinkStub } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import TwentyPersonPanel from '../TwentyPersonPanel.vue';

const { getPerson, createPerson, resolveConflict } = vi.hoisted(() => ({
  getPerson: vi.fn(),
  createPerson: vi.fn(),
  resolveConflict: vi.fn(),
}));

vi.mock('dashboard/api/integrations/twenty', () => ({
  default: { getPerson, createPerson, resolveConflict },
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '7' } }),
}));

const linkedRecord = {
  linked: true,
  can_create: true,
  person: {
    id: 'p1',
    url: 'https://twenty.test/object/person/p1',
    name: 'Anna Tsai',
    job_title: 'Investment Analyst',
    city: null,
    email: 'anna@acme.com',
    phone: null,
    linkedin_url: null,
    company: {
      id: 'c1',
      name: 'Acme',
      domain: 'acme.com',
      url: 'https://twenty.test/object/company/c1',
    },
  },
  opportunities: [
    {
      id: 'o1',
      name: 'Acme voice agent',
      url: 'https://twenty.test/object/opportunity/o1',
      stage: {
        value: 'PRICING_DISCUSSION',
        label: 'Pricing Discussion',
        color: 'ruby',
      },
      amount: { value: 120000.0, currency: 'TWD' },
      close_date: '2026-10-31',
    },
  ],
  notes: [
    {
      id: 'n1',
      url: 'https://twenty.test/object/note/n1',
      title: null,
      excerpt: 'Call summary\nWants a pilot in Q4',
      created_at: '2026-09-28T17:00:10.787Z',
      author: 'Jack Cheng',
    },
  ],
  notes_count: 6,
  conflicts: [],
};

const unlinkedRecord = {
  linked: false,
  can_create: true,
  person: null,
  opportunities: [],
  notes: [],
  notes_count: 0,
  conflicts: [],
};

const emailConflict = {
  type: 'field',
  field: 'email',
  inbox: 'anna@acme.com',
  twenty: 'anna.tsai@acme.io',
};

// Buttons render through the global NextButton stub, which keeps the label
// as an attribute.
const clickButton = (wrapper, label) =>
  wrapper.find(`button[label="${label}"]`).trigger('click');

const mountPanel = (contactId = 1) =>
  mount(TwentyPersonPanel, {
    props: { contactId },
    global: { stubs: { RouterLink: RouterLinkStub } },
  });

describe('TwentyPersonPanel', () => {
  it('renders the linked person, opportunities and notes', async () => {
    getPerson.mockResolvedValue({ data: linkedRecord });
    const wrapper = mountPanel();
    await flushPromises();

    expect(getPerson).toHaveBeenCalledWith(1, {
      signal: expect.any(AbortSignal),
    });
    const text = wrapper.text();
    expect(text).toContain('Anna Tsai');
    expect(text).toContain('Investment Analyst');
    expect(text).toContain('Acme');
    expect(text).toContain('anna@acme.com');
    expect(text).toContain('Acme voice agent');
    expect(text).toContain('Pricing Discussion');
    expect(text).toContain('NT$120,000');
    expect(text).toContain('Call summary');
    expect(text).toContain('Wants a pilot in Q4');
    expect(text).toContain('Jack Cheng');
    expect(text).toContain('CONVERSATION_SIDEBAR.TWENTY.VIEW_ALL_NOTES');
  });

  it('adds an unlinked contact to Twenty and renders the result', async () => {
    getPerson.mockResolvedValue({ data: unlinkedRecord });
    createPerson.mockResolvedValue({ data: linkedRecord });
    const wrapper = mountPanel();
    await flushPromises();

    expect(wrapper.text()).toContain('CONVERSATION_SIDEBAR.TWENTY.NOT_LINKED');
    await wrapper.find('button').trigger('click');
    await flushPromises();

    expect(createPerson).toHaveBeenCalledWith(1, {
      signal: expect.any(AbortSignal),
    });
    expect(wrapper.text()).toContain('Anna Tsai');
  });

  it('shows the error line when Twenty is unavailable', async () => {
    getPerson.mockRejectedValue({
      response: { status: 502, data: { error: 'twenty_unavailable' } },
    });
    const wrapper = mountPanel();
    await flushPromises();

    expect(wrapper.text()).toContain('CONVERSATION_SIDEBAR.TWENTY.UNAVAILABLE');
  });

  it('refetches when the contact changes', async () => {
    getPerson.mockResolvedValue({ data: unlinkedRecord });
    const wrapper = mountPanel();
    await flushPromises();

    await wrapper.setProps({ contactId: 2 });
    await flushPromises();

    expect(getPerson).toHaveBeenLastCalledWith(2, {
      signal: expect.any(AbortSignal),
    });
  });

  it('resolves a field conflict and re-renders from the response', async () => {
    getPerson.mockResolvedValue({
      data: { ...linkedRecord, conflicts: [emailConflict] },
    });
    resolveConflict.mockResolvedValue({ data: linkedRecord });
    const wrapper = mountPanel();
    await flushPromises();

    expect(wrapper.text()).toContain(
      'CONVERSATION_SIDEBAR.TWENTY.CONFLICTS.HEADING'
    );
    expect(wrapper.text()).toContain('anna.tsai@acme.io');

    await clickButton(
      wrapper,
      'CONVERSATION_SIDEBAR.TWENTY.CONFLICTS.USE_TWENTY'
    );
    await flushPromises();

    expect(resolveConflict).toHaveBeenCalledWith(
      { contact_id: 1, type: 'field', field: 'email', choice: 'twenty' },
      { signal: expect.any(AbortSignal) }
    );
    expect(wrapper.text()).not.toContain(
      'CONVERSATION_SIDEBAR.TWENTY.CONFLICTS.HEADING'
    );
    expect(wrapper.text()).toContain('Anna Tsai');
  });

  it('shows the reason when a resolution is rejected', async () => {
    getPerson.mockResolvedValue({
      data: { ...unlinkedRecord, conflicts: [emailConflict] },
    });
    resolveConflict.mockRejectedValue({
      response: {
        status: 422,
        data: { error: 'Another contact already has this email' },
      },
    });
    const wrapper = mountPanel();
    await flushPromises();

    expect(wrapper.text()).toContain('CONVERSATION_SIDEBAR.TWENTY.NOT_LINKED');
    await clickButton(
      wrapper,
      'CONVERSATION_SIDEBAR.TWENTY.CONFLICTS.USE_TWENTY'
    );
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'Another contact already has this email'
    );
    expect(wrapper.text()).toContain('anna.tsai@acme.io');
  });
});
