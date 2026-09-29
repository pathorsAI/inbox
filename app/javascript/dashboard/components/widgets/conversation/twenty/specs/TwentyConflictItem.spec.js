import { mount, RouterLinkStub } from '@vue/test-utils';
import TwentyConflictItem from '../TwentyConflictItem.vue';

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '7' } }),
}));

const openDialog = vi.fn();
const closeDialog = vi.fn();

const DialogStub = {
  name: 'Dialog',
  emits: ['confirm', 'close'],
  methods: { open: openDialog, close: closeDialog },
  template: `<section><button data-test="confirm-merge" @click="$emit('confirm')" /></section>`,
};

const fieldConflict = {
  type: 'field',
  field: 'email',
  inbox: 'anna@acme.com',
  twenty: 'anna.tsai@acme.io',
};

const ambiguousConflict = {
  type: 'ambiguous',
  candidates: [
    {
      id: 'p1',
      name: 'Anna Tsai',
      email: null,
      phone: '+886912345678',
      company: 'Acme',
      url: 'https://twenty.test/object/person/p1',
    },
    {
      id: 'p2',
      name: null,
      email: 'anna@other.com',
      phone: '+886912345678',
      company: null,
      url: null,
    },
  ],
};

const duplicateConflict = {
  type: 'duplicate_contact',
  contact: {
    id: 123,
    name: 'Anna',
    email: 'anna@acme.com',
    phone_number: null,
  },
};

const mountItem = (conflict, props = {}) =>
  mount(TwentyConflictItem, {
    props: { conflict, contactName: 'Anna Tsai', ...props },
    global: { stubs: { Dialog: DialogStub, RouterLink: RouterLinkStub } },
  });

// Buttons render through the global NextButton stub, which keeps the label
// as an attribute.
const buttonLabelled = (wrapper, key) =>
  wrapper.findAll(
    `button[label="CONVERSATION_SIDEBAR.TWENTY.CONFLICTS.${key}"]`
  );

describe('TwentyConflictItem', () => {
  it('shows both values of a field conflict and emits each choice', async () => {
    const wrapper = mountItem(fieldConflict);

    const text = wrapper.text();
    expect(text).toContain(
      'CONVERSATION_SIDEBAR.TWENTY.CONFLICTS.FIELD_TITLE.EMAIL'
    );
    expect(text).toContain('anna@acme.com');
    expect(text).toContain('anna.tsai@acme.io');

    await buttonLabelled(wrapper, 'USE_INBOX')[0].trigger('click');
    await buttonLabelled(wrapper, 'USE_TWENTY')[0].trigger('click');
    await buttonLabelled(wrapper, 'KEEP_BOTH')[0].trigger('click');

    expect(wrapper.emitted('resolve')).toEqual([
      [{ type: 'field', field: 'email', choice: 'inbox' }],
      [{ type: 'field', field: 'email', choice: 'twenty' }],
      [{ type: 'field', field: 'email', choice: 'dismiss' }],
    ]);
  });

  it('lists ambiguous candidates and emits the chosen person', async () => {
    const wrapper = mountItem(ambiguousConflict);

    const text = wrapper.text();
    expect(text).toContain('Anna Tsai');
    expect(text).toContain('Acme · +886912345678');
    expect(text).toContain('anna@other.com');
    expect(
      wrapper.find('a[href="https://twenty.test/object/person/p1"]').exists()
    ).toBe(true);

    await buttonLabelled(wrapper, 'LINK')[1].trigger('click');
    await buttonLabelled(wrapper, 'CREATE_NEW')[0].trigger('click');
    await buttonLabelled(wrapper, 'DONT_LINK')[0].trigger('click');

    expect(wrapper.emitted('resolve')).toEqual([
      [{ type: 'ambiguous', choice: 'person', person_id: 'p2' }],
      [{ type: 'ambiguous', choice: 'new' }],
      [{ type: 'ambiguous', choice: 'dismiss' }],
    ]);
  });

  it('merges a duplicate contact only after the dialog is confirmed', async () => {
    const wrapper = mountItem(duplicateConflict);

    expect(wrapper.findComponent(RouterLinkStub).props('to')).toEqual({
      name: 'contacts_edit',
      params: { accountId: '7', contactId: 123 },
    });

    await buttonLabelled(wrapper, 'MERGE')[0].trigger('click');
    expect(openDialog).toHaveBeenCalled();
    expect(wrapper.emitted('resolve')).toBeUndefined();

    await wrapper.find('[data-test="confirm-merge"]').trigger('click');
    expect(closeDialog).toHaveBeenCalled();

    await buttonLabelled(wrapper, 'KEEP_SEPARATE')[0].trigger('click');

    expect(wrapper.emitted('resolve')).toEqual([
      [{ type: 'duplicate_contact', other_contact_id: 123, choice: 'merge' }],
      [{ type: 'duplicate_contact', other_contact_id: 123, choice: 'dismiss' }],
    ]);
  });

  it('disables every choice while a resolution is in flight', () => {
    const wrapper = mountItem(fieldConflict, { isResolving: true });

    const buttons = wrapper.findAll('button');
    expect(buttons).toHaveLength(3);
    buttons.forEach(button =>
      expect(button.attributes('disabled')).toBeDefined()
    );
  });
});
