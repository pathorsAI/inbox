import { flushPromises, mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import NoAccounts from '../Index.vue';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const createAccount = vi.fn();

const mountPage = () =>
  mount(NoAccounts, {
    global: {
      plugins: [
        createStore({
          getters: {
            getCurrentUser: () => ({ email: 'agent@example.com' }),
          },
          modules: {
            globalConfig: {
              namespaced: true,
              getters: { isOnChatwootCloud: () => false },
            },
            accounts: {
              namespaced: true,
              actions: { create: createAccount },
            },
          },
        }),
      ],
    },
  });

describe('NoAccounts', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    delete window.location;
    window.location = '/app/no-accounts';
  });

  afterEach(() => {
    window.chatwootConfig = {};
  });

  it('creates an account and opens its dashboard when signup is enabled', async () => {
    window.chatwootConfig = { signupEnabled: 'true' };
    createAccount.mockResolvedValue(7);
    const wrapper = mountPage();

    await wrapper.find('input').setValue('  Acme Support ');
    await wrapper.find('[data-testid="create-account-form"]').trigger('submit');
    await flushPromises();

    expect(createAccount).toHaveBeenCalledWith(expect.anything(), {
      account_name: 'Acme Support',
    });
    expect(window.location).toBe('/app/accounts/7/dashboard');
  });

  it('alerts and stays on the page when the account name is taken', async () => {
    window.chatwootConfig = { signupEnabled: 'true' };
    createAccount.mockRejectedValue({ response: { status: 422 } });
    const wrapper = mountPage();

    await wrapper.find('input').setValue('Acme Support');
    await wrapper.find('[data-testid="create-account-form"]').trigger('submit');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('CREATE_ACCOUNT.API.EXIST_MESSAGE');
    expect(window.location).toBe('/app/no-accounts');
  });

  it('asks for an invite to the signed-in email under Pathors login without signup', () => {
    window.chatwootConfig = {
      signupEnabled: 'false',
      pathorsLoginEnabled: 'true',
    };
    const wrapper = mountPage();

    expect(wrapper.find('[data-testid="create-account-form"]').exists()).toBe(
      false
    );
    expect(wrapper.text()).toContain(
      'APP_GLOBAL.NO_ACCOUNTS.MESSAGE_PATHORS_INVITE'
    );
  });

  it('keeps the administrator message when neither signup nor Pathors login is on', () => {
    window.chatwootConfig = {
      signupEnabled: 'false',
      pathorsLoginEnabled: 'false',
    };
    const wrapper = mountPage();

    expect(wrapper.text()).toContain(
      'APP_GLOBAL.NO_ACCOUNTS.MESSAGE_SELF_HOSTED'
    );
  });
});
