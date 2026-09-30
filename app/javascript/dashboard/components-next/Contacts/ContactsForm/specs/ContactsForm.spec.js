import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import ContactsForm from '../ContactsForm.vue';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('shared/helpers/clipboard', () => ({ copyTextToClipboard: vi.fn() }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    currentAccount: ref(null),
    isCloudFeatureEnabled: () => false,
  }),
}));

const LINE_USER_ID = 'U4af4980629f1e8b0e5c9a1b2c3d4e5f6';
const SOCIAL = 'CONTACTS_LAYOUT.CARD.SOCIAL_MEDIA';

const contactData = {
  id: 4,
  name: 'Kai Lin',
  email: 'kai@example.com',
  additionalAttributes: {
    socialProfiles: { facebook: 'kai.fb' },
    socialLineUserId: LINE_USER_ID,
  },
};

const mountForm = props =>
  mount(ContactsForm, {
    props: { contactData, isDetailsView: true, ...props },
    global: {
      stubs: {
        ComboBox: true,
        CompanySelector: true,
        PhoneNumberInput: true,
      },
    },
  });

describe('ContactsForm', () => {
  it('saves the LINE ID inside the social profiles', async () => {
    const wrapper = mountForm();

    await wrapper
      .find(`input[placeholder="${SOCIAL}.FORM.LINE.PLACEHOLDER"]`)
      .setValue('kai.line');

    const [update] = wrapper.emitted('update').at(-1);
    expect(update.additionalAttributes.socialProfiles).toMatchObject({
      facebook: 'kai.fb',
      line: 'kai.line',
    });

    // The details page merges each update over its copy of the contact.
    await wrapper.setProps({ contactData: { ...contactData, ...update } });
    expect(wrapper.find('[data-test="line-user-id"]').exists()).toBe(true);
  });

  it('shows the LINE User ID read-only and copies it', async () => {
    const wrapper = mountForm();
    const row = wrapper.find('[data-test="line-user-id"]');

    expect(row.text()).toContain(`${SOCIAL}.LINE_USER_ID`);
    expect(row.text()).toContain(LINE_USER_ID);
    expect(row.find('input').exists()).toBe(false);
    expect(
      wrapper
        .findAll('input')
        .some(input => input.element.value === LINE_USER_ID)
    ).toBe(false);

    await row.find('button').trigger('click');

    expect(copyTextToClipboard).toHaveBeenCalledWith(LINE_USER_ID);
    expect(useAlert).toHaveBeenCalledWith('CONTACT_PANEL.COPY_SUCCESSFUL');
  });

  it('has no LINE User ID row without one', () => {
    const wrapper = mountForm({
      contactData: { ...contactData, additionalAttributes: {} },
    });

    expect(wrapper.find('[data-test="line-user-id"]').exists()).toBe(false);
  });
});
