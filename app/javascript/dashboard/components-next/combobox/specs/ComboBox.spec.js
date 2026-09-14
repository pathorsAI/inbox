import { DOMWrapper, flushPromises, mount } from '@vue/test-utils';
import { ref } from 'vue';
import ComboBox from '../ComboBox.vue';

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ref(false),
}));

// reka scrolls the highlighted option into view; jsdom has no implementation.
Element.prototype.scrollIntoView = () => {};

const OPTIONS = [
  { value: 1, label: 'Getting started' },
  { value: 2, label: 'Billing' },
  { value: 3, label: 'Security' },
];

describe('ComboBox', () => {
  let wrapper;

  const mountComboBox = (props = {}) => {
    wrapper = mount(ComboBox, {
      props: { options: OPTIONS, ...props },
      attachTo: document.body,
    });
    return wrapper;
  };

  // The dropdown is portalled to the body, outside the mounted wrapper.
  const trigger = () => wrapper.find('button');
  const searchInput = () =>
    new DOMWrapper(document.body.querySelector('input[role="combobox"]'));
  const items = () =>
    [...document.body.querySelectorAll('[role="option"]')].map(
      element => new DOMWrapper(element)
    );
  const openDropdown = async () => {
    await trigger().trigger('click');
    await flushPromises();
  };

  afterEach(() => {
    wrapper?.unmount();
    document.body.innerHTML = '';
  });

  it('opens the dropdown on trigger click and emits open', async () => {
    mountComboBox();
    expect(searchInput().exists()).toBe(false);

    await openDropdown();

    expect(searchInput().exists()).toBe(true);
    expect(items()).toHaveLength(3);
    expect(wrapper.emitted('open')).toHaveLength(1);
  });

  it('selects the highlighted option with arrow down and enter', async () => {
    mountComboBox();
    await openDropdown();
    // The first option is highlighted on open, so one arrow down moves to the second.
    expect(items()[0].attributes('data-highlighted')).toBeDefined();

    await searchInput().trigger('keydown', { key: 'ArrowDown' });
    await searchInput().trigger('keydown', { key: 'Enter' });
    await flushPromises();

    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual([2]);
    expect(searchInput().exists()).toBe(false);
  });

  it('clears the selection when the selected option is picked again', async () => {
    mountComboBox({ modelValue: 2 });
    await openDropdown();

    await items()[1].trigger('click');
    await flushPromises();

    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual(['']);
  });

  it('marks the selected option and labels the trigger with it', async () => {
    mountComboBox({ modelValue: 2 });
    await openDropdown();

    expect(trigger().text()).toContain('Billing');
    expect(items()[1].attributes('aria-selected')).toBe('true');
    expect(items()[0].attributes('aria-selected')).toBe('false');
  });

  it('filters options locally on search', async () => {
    mountComboBox();
    await openDropdown();

    await searchInput().setValue('bill');
    await flushPromises();

    expect(items().map(item => item.text())).toEqual(['Billing']);
    expect(wrapper.emitted('search').at(-1)).toEqual(['bill']);
  });

  it('emits search and keeps every option when useApiResults is set', async () => {
    mountComboBox({ useApiResults: true });
    await openDropdown();

    await searchInput().setValue('bill');
    await flushPromises();

    expect(wrapper.emitted('search').at(-1)).toEqual(['bill']);
    expect(items()).toHaveLength(3);
  });

  it('keeps the dropdown closed when disabled', async () => {
    mountComboBox({ disabled: true });

    await openDropdown();

    expect(searchInput().exists()).toBe(false);
    expect(wrapper.emitted('open')).toBeUndefined();
  });
});
