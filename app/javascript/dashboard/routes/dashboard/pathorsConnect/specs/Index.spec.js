import { flushPromises, mount } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import PathorsConnect from '../Index.vue';

const { get, connect, createAccount } = vi.hoisted(() => ({
  get: vi.fn(),
  connect: vi.fn(),
  createAccount: vi.fn(),
}));

vi.mock('dashboard/api/pathorsConnection', () => ({
  default: { get, connect, createAccount },
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const ORGANIZATION_ID = '3f1c2d4e-5a6b-4c7d-8e9f-0a1b2c3d4e5f';
const OTHER_ORGANIZATION_ID = '9e8d7c6b-5a4f-4e3d-2c1b-0a9f8e7d6c5b';
const AUTHORIZE_URL = 'https://api.pathors.test/oauth/authorize?state=token';

const accounts = [
  { id: 1, name: 'Acme Support', connected: false, organization_id: null },
  {
    id: 2,
    name: 'Beta Care',
    connected: true,
    organization_id: ORGANIZATION_ID,
  },
  {
    id: 3,
    name: 'Gamma Desk',
    connected: true,
    organization_id: OTHER_ORGANIZATION_ID,
  },
];

const mountPage = async (organizationId = ORGANIZATION_ID) => {
  const wrapper = mount(PathorsConnect, { props: { organizationId } });
  await flushPromises();
  return wrapper;
};

const radioFor = (wrapper, id) => wrapper.find(`input[id="${id}"]`);

describe('PathorsConnect', () => {
  let assign;

  beforeEach(() => {
    vi.clearAllMocks();
    assign = vi.fn();
    delete window.location;
    window.location = { assign };
  });

  it('does not load anything for a link without a valid organization', async () => {
    const wrapper = await mountPage('org-1');

    expect(get).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain('PATHORS_CONNECT.INVALID_LINK');
  });

  it('shows each administered account with its Pathors binding', async () => {
    get.mockResolvedValue({ data: { accounts, can_create_account: false } });

    const wrapper = await mountPage();

    const text = wrapper.text();
    expect(text).toContain('Acme Support');
    expect(text).toContain('PATHORS_CONNECT.STATUS.NOT_CONNECTED');
    expect(text).toContain('PATHORS_CONNECT.STATUS.SAME_ORGANIZATION');
    expect(text).toContain('PATHORS_CONNECT.OTHER_ORGANIZATION_HINT');
    expect(text).not.toContain('PATHORS_CONNECT.NEW_ACCOUNT.LABEL');

    expect(
      radioFor(wrapper, 'pathors-connect-account-1').attributes('disabled')
    ).toBeUndefined();
    expect(
      radioFor(wrapper, 'pathors-connect-account-2').attributes('disabled')
    ).toBeUndefined();
    expect(
      radioFor(wrapper, 'pathors-connect-account-3').attributes('disabled')
    ).toBeDefined();
    expect(wrapper.find('a').attributes('href')).toBe(
      '/app/accounts/3/settings/integrations/pathors'
    );
  });

  it('hands off to Pathors for the chosen account', async () => {
    get.mockResolvedValue({ data: { accounts, can_create_account: false } });
    connect.mockResolvedValue({ data: { authorize_url: AUTHORIZE_URL } });
    const wrapper = await mountPage();

    await radioFor(wrapper, 'pathors-connect-account-1').trigger('change');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(connect).toHaveBeenCalledWith({
      accountId: 1,
      organizationId: ORGANIZATION_ID,
    });
    expect(assign).toHaveBeenCalledWith(AUTHORIZE_URL);
  });

  it('shows the error the backend refused with', async () => {
    get.mockResolvedValue({ data: { accounts, can_create_account: false } });
    connect.mockRejectedValue({
      response: { data: { error: 'Only an administrator can connect it.' } },
    });
    const wrapper = await mountPage();

    await radioFor(wrapper, 'pathors-connect-account-2').trigger('change');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'Only an administrator can connect it.'
    );
    expect(assign).not.toHaveBeenCalled();
  });

  it('creates a new account when the user administers none', async () => {
    get.mockResolvedValue({ data: { accounts: [], can_create_account: true } });
    createAccount.mockResolvedValue({
      data: { account_id: 9, authorize_url: AUTHORIZE_URL },
    });
    const wrapper = await mountPage();

    const submit = wrapper.find('button[type="submit"]');
    expect(submit.attributes('disabled')).toBeDefined();

    await wrapper.find('input[type="text"]').setValue('  Delta Line ');
    expect(submit.attributes('disabled')).toBeUndefined();
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(createAccount).toHaveBeenCalledWith({
      accountName: 'Delta Line',
      organizationId: ORGANIZATION_ID,
    });
    expect(assign).toHaveBeenCalledWith(AUTHORIZE_URL);
  });

  it('says so when there is nothing to choose from', async () => {
    get.mockResolvedValue({
      data: { accounts: [], can_create_account: false },
    });

    const wrapper = await mountPage();

    expect(wrapper.text()).toContain('PATHORS_CONNECT.NO_ACCOUNTS');
    expect(wrapper.find('form').exists()).toBe(false);
  });
});
