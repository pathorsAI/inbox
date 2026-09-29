import { flushPromises, mount } from '@vue/test-utils';
import { ref } from 'vue';
import ContactsFilterBar from '../ContactsFilterBar.vue';

// Popover reads the reading direction from the store.
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ref(false),
}));

// Below sm every pill collapses into the overflow menu (and Popover turns into a modal).
const isNarrow = ref(false);
vi.mock('@vueuse/core', async importOriginal => ({
  ...(await importOriginal()),
  useBreakpoints: () => ({ smaller: () => isNarrow }),
}));

const QUICK = 'CONTACTS_LAYOUT.FILTER.QUICK';

const condition = (attributeKey, filterOperator, values, queryOperator) => ({
  attributeKey,
  filterOperator,
  values,
  queryOperator: queryOperator ?? 'and',
  attributeModel: 'standard',
});

const city = condition('city', 'contains', 'Taipei');

describe('ContactsFilterBar', () => {
  let wrapper;

  const mountBar = props => {
    wrapper = mount(ContactsFilterBar, {
      props: { showTwenty: true, ...props },
      slots: {
        advanced: '<div data-test="advanced-panel" />',
      },
      global: { renderStubDefaultSlot: true, stubs: { teleport: true } },
      attachTo: document.body,
    });
    return wrapper;
  };

  // Without messages, the i18n key is the rendered text. The bar's invisible measuring copy
  // renders first, so the last match is the one on screen.
  const buttonWithText = text =>
    wrapper
      .findAll('button')
      .filter(button => button.text() === text)
      .at(-1);

  const openPill = async key => {
    await buttonWithText(`${QUICK}.${key}.LABEL`).trigger('click');
    await flushPromises();
  };

  const lastApply = () => wrapper.emitted('apply').at(-1)[0];

  afterEach(() => {
    wrapper?.unmount();
    isNarrow.value = false;
    vi.useRealTimers();
    document.body.innerHTML = '';
  });

  it('renders the pills in priority order and the advanced button', () => {
    mountBar();
    const labels = wrapper
      .findAll('button')
      .map(button => button.text())
      .filter(text => text.startsWith(QUICK));

    // The measuring copy renders first, then the visible row.
    expect(labels.slice(-7)).toEqual([
      `${QUICK}.LAST_ACTIVITY.LABEL`,
      `${QUICK}.LABELS.LABEL`,
      `${QUICK}.COMPANY.LABEL`,
      `${QUICK}.COUNTRY.LABEL`,
      `${QUICK}.CONTACT_METHOD.LABEL`,
      `${QUICK}.TWENTY_STATUS.LABEL`,
      `${QUICK}.ADVANCED`,
    ]);
    expect(buttonWithText(`${QUICK}.SAVE_SEGMENT`)).toBeUndefined();
  });

  it('leaves the Twenty pill out while the integration is off', () => {
    mountBar({ showTwenty: false });
    expect(buttonWithText(`${QUICK}.TWENTY_STATUS.LABEL`)).toBeUndefined();
  });

  it('applies a choice as soon as it is clicked', async () => {
    mountBar({ filters: [city] });
    await openPill('TWENTY_STATUS');
    await buttonWithText(`${QUICK}.TWENTY_STATUS.LINKED`).trigger('click');

    expect(lastApply()).toEqual([
      city,
      condition('twenty_status', 'equal_to', { id: 'linked', name: 'linked' }),
    ]);
  });

  it('applies both contact methods as two AND conditions', async () => {
    mountBar();
    await openPill('CONTACT_METHOD');
    await buttonWithText(`${QUICK}.CONTACT_METHOD.BOTH`).trigger('click');

    expect(lastApply()).toEqual([
      condition('email', 'is_present', ''),
      condition('phone_number', 'is_present', ''),
    ]);
  });

  it('turns a last activity preset into a date', async () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date(2026, 8, 30, 10));
    mountBar();
    await openPill('LAST_ACTIVITY');
    await buttonWithText(`${QUICK}.LAST_ACTIVITY.LAST_7_DAYS`).trigger('click');

    expect(lastApply()).toEqual([
      condition('last_activity_at', 'is_greater_than', '2026-09-23'),
    ]);
  });

  it('applies the company text on submit', async () => {
    mountBar();
    await openPill('COMPANY');
    await wrapper.find('input').setValue(' Acme ');
    await wrapper.find('form').trigger('submit');

    expect(lastApply()).toEqual([
      condition('company_name', 'contains', 'Acme'),
    ]);
  });

  it('applies the picked labels together', async () => {
    mountBar({ labels: [{ title: 'newsletter' }, { title: 'vip' }] });
    await openPill('LABELS');
    await buttonWithText('newsletter').trigger('click');
    await buttonWithText('vip').trigger('click');
    expect(wrapper.emitted('apply')).toBeUndefined();

    await buttonWithText(`${QUICK}.APPLY`).trigger('click');

    expect(lastApply()).toEqual([
      condition('labels', 'equal_to', [
        { id: 'newsletter', name: 'newsletter' },
        { id: 'vip', name: 'vip' },
      ]),
    ]);
  });

  it('clears one pill with its clear button', async () => {
    const country = condition('country_code', 'equal_to', {
      id: 'TW',
      name: 'Taiwan',
    });
    mountBar({ filters: [country, city] });

    const clearButtons = wrapper.findAll(
      `button[aria-label="${QUICK}.CLEAR_PILL"]`
    );
    await clearButtons.at(-1).trigger('click');

    expect(lastApply()).toEqual([city]);
  });

  it('counts conditions no pill owns on the advanced button', () => {
    mountBar({ filters: [city] });
    expect(buttonWithText(`${QUICK}.ADVANCED_COUNT`)).toBeDefined();
  });

  it('opens the advanced panel in a popover', async () => {
    mountBar();
    await buttonWithText(`${QUICK}.ADVANCED`).trigger('click');
    await flushPromises();

    expect(wrapper.emitted('openAdvanced')).toHaveLength(1);
    expect(wrapper.find('[data-test="advanced-panel"]').exists()).toBe(true);
  });

  it('disables the pills but not the advanced button when a condition joins with OR', async () => {
    const orFilters = [
      condition('name', 'equal_to', 'Anna', 'or'),
      condition('labels', 'equal_to', [{ id: 'vip', name: 'vip' }]),
    ];
    mountBar({ filters: orFilters });

    const pill = buttonWithText(`${QUICK}.COMPANY.LABEL`);
    expect(pill.attributes('disabled')).toBeDefined();
    await pill.trigger('click');
    await flushPromises();
    expect(wrapper.find('form').exists()).toBe(false);

    const advanced = buttonWithText(`${QUICK}.ADVANCED_COUNT`);
    expect(advanced.attributes('disabled')).toBeUndefined();
    await advanced.trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-test="advanced-panel"]').exists()).toBe(true);
  });

  it('collapses the pills into the overflow menu and edits them from there', async () => {
    isNarrow.value = true;
    const labels = condition('labels', 'equal_to', [
      { id: 'vip', name: 'vip' },
    ]);
    mountBar({ filters: [labels] });

    expect(buttonWithText(`${QUICK}.MORE_COUNT`)).toBeDefined();
    await buttonWithText(`${QUICK}.MORE_COUNT`).trigger('click');
    await flushPromises();
    await buttonWithText(`${QUICK}.COUNTRY.LABEL`).trigger('click');
    await buttonWithText('Taiwan').trigger('click');

    expect(lastApply()).toEqual([
      labels,
      condition('country_code', 'equal_to', { id: 'TW', name: 'Taiwan' }),
    ]);
  });

  it('offers saving and clearing once anything is applied', async () => {
    mountBar({ filters: [city] });
    await buttonWithText(`${QUICK}.SAVE_SEGMENT`).trigger('click');
    await buttonWithText(`${QUICK}.CLEAR_ALL`).trigger('click');

    expect(wrapper.emitted('createSegment')).toHaveLength(1);
    expect(wrapper.emitted('clearAll')).toHaveLength(1);
  });
});
