import { defineComponent, ref } from 'vue';
import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import PathorsHandoff from '../PathorsHandoff.vue';
import { provideMessageContext } from '../../provider.js';

withFullI18n();

const buildTranscript = count =>
  Array.from({ length: count }, (_, index) => ({
    role: index % 2 === 0 ? 'assistant' : 'user',
    content: `turn ${index + 1}`,
    timestamp: `2026-09-28T14:${String(20 + index).padStart(2, '0')}:00Z`,
  }));

const mountHandoff = (data = {}) => {
  const TestHost = defineComponent({
    components: { PathorsHandoff },
    setup() {
      provideMessageContext({
        contentAttributes: ref({
          data: {
            transcript: buildTranscript(5),
            variables: {
              customer_name: '陳志明',
              extra_bed: true,
              callback_phone: null,
            },
            transferredAt: '2026-09-28T14:32:00Z',
            aiDurationSeconds: 192,
            ...data,
          },
        }),
      });
    },
    template: '<PathorsHandoff />',
  });

  return mount(TestHost);
};

const turnTexts = wrapper =>
  wrapper.findAll('[data-test-id="handoff-turn"] p').map(turn => turn.text());

describe('PathorsHandoff', () => {
  it('shows the handoff time and how long the AI talked', () => {
    const wrapper = mountHandoff();

    expect(wrapper.text()).toContain('AI handoff summary');
    expect(wrapper.text()).toContain('14:32 handed off · AI talked 3m 12s');
  });

  it('lists variables with their raw keys and marks missing values', () => {
    const wrapper = mountHandoff();
    const keys = wrapper.findAll('dt').map(item => item.text());
    const values = wrapper.findAll('dd').map(item => item.text());

    expect(keys).toEqual(['customer_name', 'extra_bed', 'callback_phone']);
    expect(values).toEqual(['陳志明', 'Yes', 'Not captured']);
    expect(wrapper.text()).toContain('Captured variables · 2');
  });

  it('says so when no variables were captured', () => {
    const wrapper = mountHandoff({ variables: {} });

    expect(wrapper.find('dl').exists()).toBe(false);
    expect(wrapper.text()).toContain('No variables captured before handoff');
  });

  it('shows the last three turns until expanded', async () => {
    const wrapper = mountHandoff();

    expect(turnTexts(wrapper)).toEqual(['turn 3', 'turn 4', 'turn 5']);

    const toggle = wrapper.find('button');
    expect(toggle.text()).toBe('Show 2 earlier');

    await toggle.trigger('click');

    expect(turnTexts(wrapper)).toEqual([
      'turn 1',
      'turn 2',
      'turn 3',
      'turn 4',
      'turn 5',
    ]);
    expect(wrapper.find('button').text()).toBe('Collapse');
  });

  it('has no toggle when there are three turns or fewer', () => {
    const wrapper = mountHandoff({ transcript: buildTranscript(3) });

    expect(turnTexts(wrapper)).toHaveLength(3);
    expect(wrapper.find('button').exists()).toBe(false);
  });

  it('hides the transcript section when the transcript is empty', () => {
    const wrapper = mountHandoff({ transcript: [] });

    expect(wrapper.find('[data-test-id="handoff-transcript"]').exists()).toBe(
      false
    );
  });
});
