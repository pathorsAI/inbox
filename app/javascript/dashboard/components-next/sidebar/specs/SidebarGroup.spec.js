import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import SidebarGroup from '../SidebarGroup.vue';
import { provideSidebarContext, useSidebarExpandedGroups } from '../provider';

const push = vi.fn();
const uiSettings = ref({});
const updateUISettings = vi.fn(settings => {
  uiSettings.value = { ...uiSettings.value, ...settings };
});

vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({ uiSettings, updateUISettings }),
}));

vi.mock('dashboard/composables/store.js', () => ({
  useMapGetter: () => ref(0),
}));

vi.mock('dashboard/composables/usePolicy', () => ({
  usePolicy: () => ({ shouldShow: () => true }),
}));

vi.mock('vue-router', () => ({
  useRoute: () => ({ path: '/elsewhere', name: 'elsewhere', params: {} }),
  useRouter: () => ({
    push,
    resolve: to => ({ path: `/${to.name}`, meta: {} }),
    getRoutes: () => [],
  }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const groups = [
  {
    name: 'Conversation',
    label: 'Conversations',
    children: [
      { name: 'All', label: 'All', to: { name: 'home' } },
      { name: 'Mentions', label: 'Mentions', to: { name: 'mentions' } },
    ],
  },
  {
    name: 'Reports',
    label: 'Reports',
    children: [
      { name: 'Overview', label: 'Overview', to: { name: 'overview' } },
    ],
  },
];

const PolicyStub = {
  props: ['as', 'permissions', 'featureFlag'],
  template: '<li><slot /></li>',
};

const mountGroups = () =>
  mount(
    {
      components: { SidebarGroup },
      setup() {
        const {
          expandedItems,
          isItemExpanded,
          toggleExpandedItem,
          expandItem,
        } = useSidebarExpandedGroups();

        provideSidebarContext({
          expandedItems,
          isItemExpanded,
          toggleExpandedItem,
          expandItem,
          isCollapsed: ref(false),
          sidebarWidth: ref(200),
          isResizing: ref(false),
        });

        return { groups };
      },
      template:
        '<ul><SidebarGroup v-for="group in groups" :key="group.name" v-bind="group" /></ul>',
    },
    {
      global: {
        stubs: {
          Icon: true,
          Policy: PolicyStub,
          SidebarGroupLeaf: { template: '<li />' },
          SidebarSubGroup: { template: '<li />' },
        },
      },
    }
  );

// The chevron is the only aria-expanded control a group renders.
const chevrons = wrapper => wrapper.findAll('button[aria-expanded]');
const names = wrapper => wrapper.findAll('[role="button"]');

describe('SidebarGroup', () => {
  beforeEach(() => {
    uiSettings.value = {};
    push.mockClear();
    updateUISettings.mockClear();
  });

  it('keeps several groups open at the same time', async () => {
    const wrapper = mountGroups();

    await chevrons(wrapper)[0].trigger('click');
    await chevrons(wrapper)[1].trigger('click');

    expect(
      chevrons(wrapper).map(chevron => chevron.attributes('aria-expanded'))
    ).toEqual(['true', 'true']);
  });

  it('toggles on the chevron without navigating', async () => {
    const wrapper = mountGroups();

    await chevrons(wrapper)[0].trigger('click');
    expect(chevrons(wrapper)[0].attributes('aria-expanded')).toBe('true');
    expect(push).not.toHaveBeenCalled();

    await chevrons(wrapper)[0].trigger('click');
    expect(chevrons(wrapper)[0].attributes('aria-expanded')).toBe('false');
    expect(push).not.toHaveBeenCalled();
  });

  it('navigates to the first child and expands when the name is clicked', async () => {
    const wrapper = mountGroups();

    await names(wrapper)[0].trigger('click');

    expect(push).toHaveBeenCalledWith({ name: 'home' });
    expect(chevrons(wrapper)[0].attributes('aria-expanded')).toBe('true');
  });

  it('persists the open groups to uiSettings', async () => {
    const wrapper = mountGroups();

    await chevrons(wrapper)[0].trigger('click');
    expect(updateUISettings).toHaveBeenLastCalledWith({
      sidebar_expanded_groups: ['Conversation'],
    });

    await chevrons(wrapper)[1].trigger('click');
    expect(updateUISettings).toHaveBeenLastCalledWith({
      sidebar_expanded_groups: ['Conversation', 'Reports'],
    });
  });

  it('hydrates the open groups from uiSettings', () => {
    uiSettings.value = { sidebar_expanded_groups: ['Reports'] };

    const wrapper = mountGroups();

    expect(
      chevrons(wrapper).map(chevron => chevron.attributes('aria-expanded'))
    ).toEqual(['false', 'true']);
  });
});
