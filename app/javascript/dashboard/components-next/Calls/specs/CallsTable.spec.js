import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { primaryCallState } from 'dashboard/helper/pathorsCallState';
import CallsTable from '../CallsTable.vue';

withFullI18n('zh_TW');

const NOW = Date.parse('2026-10-18T10:00:00Z');

const buildCall = overrides => ({
  id: 77,
  provider: 'pathors',
  status: 'completed',
  startedAt: '2026-10-18T09:00:00Z',
  durationSeconds: 120,
  fromNumber: '+886933963188',
  inbox: { name: '派斯科技代表號碼' },
  ...overrides,
});

const mountTable = call =>
  mount(CallsTable, {
    props: {
      sections: [
        {
          key: 'today',
          rows: [{ call, state: primaryCallState(call, { now: NOW }) }],
        },
      ],
      now: NOW,
    },
  });

const badge = wrapper =>
  wrapper.find('[data-test-id="call-row-interruptions"]');

const withInterruptions = interruptions =>
  mountTable(
    buildCall({ live: { seq: 4, turns: 6, interruptions, transcript: [] } })
  );

describe('CallsTable', () => {
  describe('interruptions beside the time', () => {
    it('shows nothing for a call never interrupted, or with no live data', () => {
      expect(badge(withInterruptions(0)).exists()).toBe(false);
      expect(badge(withInterruptions(null)).exists()).toBe(false);
      expect(badge(mountTable(buildCall())).exists()).toBe(false);
    });

    it('shows the count quietly up to the limit', () => {
      [2, 3].forEach(count => {
        const el = badge(withInterruptions(count));
        expect(el.exists()).toBe(true);
        expect(el.text()).toContain(String(count));
        expect(el.classes()).toContain('text-n-slate-10');
        expect(el.classes()).not.toContain('text-n-amber-11');
      });
    });

    it('turns amber once the count goes past the limit', () => {
      const el = badge(withInterruptions(4));
      expect(el.classes()).toContain('text-n-amber-11');
      expect(el.classes()).toContain('font-medium');
    });

    it('says what the number means to a hover and a screen reader', () => {
      const el = badge(withInterruptions(2));
      expect(el.attributes('title')).toBe('被打斷 2 次');
      expect(el.find('.sr-only').text()).toBe('被打斷 2 次');
      expect(el.find('[aria-hidden="true"] .i-lucide-hand').exists()).toBe(
        true
      );
    });

    it('shows on a call that is still on the line', () => {
      const el = badge(
        mountTable(
          buildCall({
            status: 'in-progress',
            startedAt: '2026-10-18T09:58:00Z',
            live: { seq: 4, turns: 6, interruptions: 1, transcript: [] },
          })
        )
      );
      expect(el.exists()).toBe(true);
      expect(el.text()).toContain('1');
    });
  });
});
