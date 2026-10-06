import { flushPromises, mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { withFullI18n } from 'test-i18n';
import { useAlert } from 'dashboard/composables';
import Github from '../Github.vue';
import Integration from '../Integration.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';

const { getRepositories, updateSettings, routerReplace } = vi.hoisted(() => ({
  getRepositories: vi.fn(),
  updateSettings: vi.fn(),
  routerReplace: vi.fn(),
}));

vi.mock('dashboard/api/integrations/github', () => ({
  default: { getRepositories, updateSettings },
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

vi.mock('vue-router', async importOriginal => ({
  ...(await importOriginal()),
  useRouter: () => ({ replace: routerReplace }),
  useRoute: () => ({ path: '/app/accounts/1/settings/integrations/github' }),
}));

const i18n = withFullI18n('en');

const INSTALL_URL =
  'https://github.com/apps/pathors-inbox/installations/new?state=signed';

const installedHook = (overrides = {}) => ({
  id: 5,
  app_id: 'github',
  status: true,
  reference_id: '81234567',
  settings: {},
  reauthorization_required: false,
  ...overrides,
});

const buildStore = hooks => {
  const refreshedHooks = { value: null };
  const get = vi.fn(({ commit }) => {
    if (refreshedHooks.value) commit('setHooks', refreshedHooks.value);
  });
  const store = createStore({
    modules: {
      integrations: {
        namespaced: true,
        state: {
          records: [
            {
              id: 'github',
              name: 'GitHub',
              description: 'Open GitHub issues from conversations.',
              enabled: Boolean(hooks.length),
              action: INSTALL_URL,
              hooks,
            },
          ],
        },
        getters: {
          getIntegration: state => id =>
            state.records.find(record => record.id === id) ?? {},
        },
        mutations: {
          setHooks: (state, newHooks) => {
            state.records[0].hooks = newHooks;
          },
        },
        actions: { get },
      },
    },
  });
  return { store, get, refreshedHooks };
};

const mountPage = async ({ hooks = [], props = {} } = {}) => {
  const { store, get, refreshedHooks } = buildStore(hooks);
  const wrapper = mount(Github, {
    props,
    global: {
      plugins: [store],
      stubs: {
        Integration: true,
        BaseSettingsHeader: true,
        WootLoadingState: true,
      },
    },
  });
  await flushPromises();
  return { wrapper, get, refreshedHooks };
};

const integrationCard = wrapper => wrapper.findComponent(Integration);

describe('Github settings page', () => {
  beforeEach(() => {
    i18n.global.locale.value = 'en';
    getRepositories.mockResolvedValue({
      data: ['pathorsAI/pathors', 'pathorsAI/inbox'],
    });
    updateSettings.mockResolvedValue({ data: {} });
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('offers the install link when nothing is connected', async () => {
    const { wrapper } = await mountPage();

    expect(integrationCard(wrapper).props('integrationEnabled')).toBe(false);
    expect(integrationCard(wrapper).props('integrationAction')).toBe(
      INSTALL_URL
    );
    expect(wrapper.text()).not.toContain('Repository for new issues');
    expect(getRepositories).not.toHaveBeenCalled();
  });

  it('treats a legacy token hook as not connected', async () => {
    const { wrapper } = await mountPage({
      hooks: [installedHook({ reference_id: null })],
    });

    expect(integrationCard(wrapper).props('integrationEnabled')).toBe(false);
    expect(integrationCard(wrapper).props('integrationAction')).toBe(
      INSTALL_URL
    );
  });

  it('asks to reconnect when the installation lost access', async () => {
    const { wrapper } = await mountPage({
      hooks: [
        installedHook({
          reauthorization_required: true,
          settings: { repository: 'pathorsAI/inbox' },
        }),
      ],
    });

    expect(wrapper.text()).toContain('GitHub needs to be reconnected');
    expect(wrapper.text()).toContain(
      'The GitHub App was uninstalled, suspended, or lost access to the selected repository.'
    );
    expect(wrapper.find(`a[href="${INSTALL_URL}"]`).exists()).toBe(true);
    expect(integrationCard(wrapper).props('integrationEnabled')).toBe(true);
    expect(integrationCard(wrapper).props('integrationAction')).toBe(
      'disconnect'
    );
  });

  it('saves the chosen repository and label, then shows them', async () => {
    const { wrapper, get, refreshedHooks } = await mountPage({
      hooks: [installedHook()],
    });

    expect(getRepositories).toHaveBeenCalledTimes(1);
    expect(wrapper.text()).toContain(
      'Only repositories the GitHub App can access are listed.'
    );
    const comboBox = wrapper.findComponent(ComboBox);
    expect(comboBox.props('options')).toEqual([
      { value: 'pathorsAI/pathors', label: 'pathorsAI/pathors' },
      { value: 'pathorsAI/inbox', label: 'pathorsAI/inbox' },
    ]);

    comboBox.vm.$emit('update:modelValue', 'pathorsAI/inbox');
    await wrapper.find('input').setValue('  support ');
    refreshedHooks.value = [
      installedHook({
        settings: { repository: 'pathorsAI/inbox', label: 'support' },
      }),
    ];
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Save')
      .trigger('click');
    await flushPromises();

    expect(updateSettings).toHaveBeenCalledWith({
      repository: 'pathorsAI/inbox',
      label: 'support',
    });
    expect(useAlert).toHaveBeenCalledWith('GitHub settings saved');
    expect(get).toHaveBeenCalledTimes(2);
    expect(wrapper.findComponent(ComboBox).exists()).toBe(false);
    expect(wrapper.text()).toContain('Where issues are opened');
    expect(
      wrapper.find('a[href="https://github.com/pathorsAI/inbox"]').text()
    ).toBe('pathorsAI/inbox');
    expect(wrapper.text()).toContain('support');
  });

  it('shows the server error when the repository is refused', async () => {
    updateSettings.mockRejectedValue({
      response: {
        status: 422,
        data: { error: 'Repository is not part of this installation' },
      },
    });
    const { wrapper } = await mountPage({ hooks: [installedHook()] });

    wrapper
      .findComponent(ComboBox)
      .vm.$emit('update:modelValue', 'pathorsAI/pathors');
    await wrapper.vm.$nextTick();
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Save')
      .trigger('click');
    await flushPromises();

    expect(wrapper.text()).toContain(
      'Repository is not part of this installation'
    );
    expect(useAlert).not.toHaveBeenCalled();
    expect(wrapper.findComponent(ComboBox).exists()).toBe(true);
  });

  it('says so when the installation exposes no repositories', async () => {
    getRepositories.mockResolvedValue({ data: [] });
    const { wrapper } = await mountPage({ hooks: [installedHook()] });

    expect(wrapper.text()).toContain(
      "The GitHub App can't access any repositories yet."
    );
  });

  it('refetches the hook when GitHub refuses the repository listing', async () => {
    getRepositories.mockRejectedValue({
      response: { status: 422, data: { error: 'Bad credentials' } },
    });
    const { wrapper, get } = await mountPage({ hooks: [installedHook()] });

    expect(wrapper.text()).toContain("Couldn't load repositories from GitHub.");
    expect(get).toHaveBeenCalledTimes(2);
  });

  it('lets the repository be changed from the connected summary', async () => {
    const { wrapper } = await mountPage({
      hooks: [
        installedHook({
          settings: { repository: 'pathorsAI/inbox', label: '' },
        }),
      ],
    });

    expect(wrapper.text()).toContain('Where issues are opened');
    expect(wrapper.text()).toContain('None');
    expect(getRepositories).not.toHaveBeenCalled();

    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Change')
      .trigger('click');
    await flushPromises();

    expect(getRepositories).toHaveBeenCalledTimes(1);
    expect(wrapper.findComponent(ComboBox).props('modelValue')).toBe(
      'pathorsAI/inbox'
    );

    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Cancel')
      .trigger('click');

    expect(wrapper.findComponent(ComboBox).exists()).toBe(false);
    expect(wrapper.text()).toContain('Where issues are opened');
  });

  it.each([
    [
      { error: 'installation_not_verified' },
      "The GitHub account you signed in with can't see that installation",
    ],
    [
      { error: 'connection_failed' },
      'Something went wrong while connecting GitHub.',
    ],
    [
      { setupAction: 'request' },
      'Waiting for your GitHub organization owner to approve the installation.',
    ],
  ])(
    'shows the install redirect notice for %o and clears the query',
    async (props, message) => {
      const { wrapper } = await mountPage({ props });

      expect(wrapper.text()).toContain(message);
      expect(routerReplace).toHaveBeenCalledWith(
        '/app/accounts/1/settings/integrations/github'
      );
    }
  );

  it('leaves the URL alone without an install redirect query', async () => {
    await mountPage();

    expect(routerReplace).not.toHaveBeenCalled();
  });

  it('renders the zh_TW copy', async () => {
    i18n.global.locale.value = 'zh_TW';
    const { wrapper } = await mountPage({
      hooks: [
        installedHook({
          settings: { repository: 'pathorsAI/inbox', label: 'support' },
        }),
      ],
      props: { setupAction: 'request' },
    });

    expect(wrapper.text()).toContain('Issue 建立位置');
    expect(wrapper.text()).toContain('儲存庫');
    expect(wrapper.text()).toContain('正在等待你的 GitHub 組織擁有者核准安裝');
  });
});
