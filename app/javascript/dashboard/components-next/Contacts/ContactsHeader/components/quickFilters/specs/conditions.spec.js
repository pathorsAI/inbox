import snakecaseKeys from 'snakecase-keys';
import filterQueryGenerator from 'dashboard/helper/filterQueryGenerator';
import {
  CONTACT_METHOD,
  QUICK_FILTER,
  QUICK_FILTER_ORDER,
  clearQuickFilter,
  daysAgo,
  hasOrJoin,
  lastActivityPreset,
  normalizeQueryOperators,
  readQuickFilters,
  setQuickFilter,
} from '../conditions';

const TODAY = new Date(2026, 8, 30, 15, 30);

const condition = (attributeKey, filterOperator, values, extra = {}) => ({
  attributeKey,
  filterOperator,
  values,
  queryOperator: 'and',
  attributeModel: 'standard',
  ...extra,
});

const city = condition('city', 'contains', 'Taipei');
const name = condition('name', 'equal_to', 'Anna');

// What the list request receives for a set of stored conditions.
const requestPayload = conditions =>
  filterQueryGenerator(conditions.map(item => snakecaseKeys(item))).payload;

describe('quick filter conditions', () => {
  describe('readQuickFilters', () => {
    it('reads every pill from the shapes the advanced panel stores', () => {
      const conditions = [
        condition('last_activity_at', 'is_greater_than', '2026-09-23'),
        condition('labels', 'equal_to', [
          { id: 'newsletter', name: 'newsletter' },
          { id: 'notification', name: 'notification' },
        ]),
        condition('company_name', 'contains', 'Acme'),
        condition('country_code', 'equal_to', { id: 'TW', name: 'Taiwan' }),
        condition('email', 'is_present', ''),
        condition(
          'crm_status',
          'equal_to',
          { id: '需要處理', name: '需要處理' },
          { attributeModel: 'customAttributes' }
        ),
        city,
      ];

      expect(readQuickFilters(conditions, QUICK_FILTER_ORDER)).toEqual({
        values: {
          LAST_ACTIVITY: '2026-09-23',
          LABELS: ['newsletter', 'notification'],
          COMPANY: 'Acme',
          COUNTRY: 'TW',
          CONTACT_METHOD: CONTACT_METHOD.EMAIL,
          CRM_STATUS: '需要處理',
        },
        counts: {
          LAST_ACTIVITY: 1,
          LABELS: 1,
          COMPANY: 1,
          COUNTRY: 1,
          CONTACT_METHOD: 1,
          CRM_STATUS: 1,
        },
        advancedCount: 1,
      });
    });

    it('leaves pills unset and counts other operators as advanced', () => {
      const conditions = [
        condition('labels', 'not_equal_to', [{ id: 'vip', name: 'vip' }]),
        condition('company_name', 'equal_to', 'Acme'),
        condition('last_activity_at', 'is_less_than', '2026-01-01'),
        condition('email', 'is_not_present', ''),
      ];

      const { values, advancedCount } = readQuickFilters(
        conditions,
        QUICK_FILTER_ORDER
      );

      expect(Object.values(values).every(value => value === null)).toBe(true);
      expect(advancedCount).toBe(4);
    });

    it('counts conditions of a pill that is not on the bar as advanced', () => {
      const pills = QUICK_FILTER_ORDER.filter(
        pill => pill !== QUICK_FILTER.CRM_STATUS
      );
      const conditions = [
        condition('crm_status', 'equal_to', { id: 'Linked', name: 'Linked' }),
      ];

      const { values, advancedCount } = readQuickFilters(conditions, pills);

      expect(values).not.toHaveProperty(QUICK_FILTER.CRM_STATUS);
      expect(advancedCount).toBe(1);
    });

    it('reads a legacy Twenty status condition as advanced', () => {
      const conditions = [
        condition('twenty_status', 'equal_to', { id: 'linked', name: 'x' }),
      ];

      const { values, advancedCount } = readQuickFilters(
        conditions,
        QUICK_FILTER_ORDER
      );

      expect(values[QUICK_FILTER.CRM_STATUS]).toBeNull();
      expect(advancedCount).toBe(1);
    });

    it.each([
      [['phone_number'], CONTACT_METHOD.PHONE, 1],
      [['email', 'phone_number'], CONTACT_METHOD.BOTH, 2],
    ])('reads contact method from %j', (attributes, method, count) => {
      const conditions = attributes.map(key =>
        condition(key, 'is_present', '')
      );

      const { values, counts } = readQuickFilters(conditions, [
        QUICK_FILTER.CONTACT_METHOD,
      ]);

      expect(values.CONTACT_METHOD).toBe(method);
      expect(counts.CONTACT_METHOD).toBe(count);
    });
  });

  describe('setQuickFilter', () => {
    it.each([
      [
        QUICK_FILTER.LAST_ACTIVITY,
        '2026-09-23',
        [condition('last_activity_at', 'is_greater_than', '2026-09-23')],
        [
          {
            attribute_key: 'last_activity_at',
            filter_operator: 'is_greater_than',
            values: ['2026-09-23'],
          },
        ],
      ],
      [
        QUICK_FILTER.LABELS,
        ['newsletter', 'notification'],
        [
          condition('labels', 'equal_to', [
            { id: 'newsletter', name: 'newsletter' },
            { id: 'notification', name: 'notification' },
          ]),
        ],
        [
          {
            attribute_key: 'labels',
            filter_operator: 'equal_to',
            values: ['newsletter', 'notification'],
          },
        ],
      ],
      [
        QUICK_FILTER.COMPANY,
        'Acme',
        [condition('company_name', 'contains', 'Acme')],
        [
          {
            attribute_key: 'company_name',
            filter_operator: 'contains',
            values: ['Acme'],
          },
        ],
      ],
      [
        QUICK_FILTER.COUNTRY,
        'TW',
        [condition('country_code', 'equal_to', { id: 'TW', name: 'Taiwan' })],
        [
          {
            attribute_key: 'country_code',
            filter_operator: 'equal_to',
            values: ['TW'],
          },
        ],
      ],
      [
        QUICK_FILTER.CONTACT_METHOD,
        CONTACT_METHOD.BOTH,
        [
          condition('email', 'is_present', ''),
          condition('phone_number', 'is_present', ''),
        ],
        [
          {
            attribute_key: 'email',
            filter_operator: 'is_present',
            values: [],
            query_operator: 'and',
          },
          {
            attribute_key: 'phone_number',
            filter_operator: 'is_present',
            values: [],
          },
        ],
      ],
      [
        QUICK_FILTER.CRM_STATUS,
        'Linked',
        [
          condition(
            'crm_status',
            'equal_to',
            { id: 'Linked', name: 'Linked' },
            { attributeModel: 'customAttributes' }
          ),
        ],
        [
          {
            attribute_key: 'crm_status',
            filter_operator: 'equal_to',
            values: ['Linked'],
            attribute_model: 'customAttributes',
          },
        ],
      ],
    ])('builds %s', (pill, value, stored, request) => {
      const conditions = setQuickFilter([], pill, value);

      expect(conditions).toEqual(stored);
      expect(requestPayload(conditions)).toEqual(
        request.map(item => ({
          attribute_model: 'standard',
          query_operator: undefined,
          ...item,
        }))
      );
    });

    it('replaces the pill in place and keeps other conditions', () => {
      const conditions = [
        name,
        condition('labels', 'equal_to', [{ id: 'vip', name: 'vip' }]),
        city,
      ];

      const next = setQuickFilter(conditions, QUICK_FILTER.LABELS, [
        'newsletter',
      ]);

      expect(next).toEqual([
        name,
        condition('labels', 'equal_to', [
          { id: 'newsletter', name: 'newsletter' },
        ]),
        city,
      ]);
    });

    it('appends an unset pill after the existing conditions with AND', () => {
      const next = setQuickFilter([name], QUICK_FILTER.COMPANY, 'Acme');

      expect(next).toEqual([
        name,
        condition('company_name', 'contains', 'Acme'),
      ]);
      expect(requestPayload(next)[0].query_operator).toBe('and');
    });

    it('does not let a stale trailing OR start joining once something is appended', () => {
      const next = setQuickFilter(
        [{ ...name, queryOperator: 'or' }],
        QUICK_FILTER.COMPANY,
        'Acme'
      );

      expect(next.map(item => item.queryOperator)).toEqual(['and', 'and']);
    });

    it('narrows contact method from both to one condition', () => {
      const both = setQuickFilter(
        [city],
        QUICK_FILTER.CONTACT_METHOD,
        CONTACT_METHOD.BOTH
      );

      const next = setQuickFilter(
        both,
        QUICK_FILTER.CONTACT_METHOD,
        CONTACT_METHOD.PHONE
      );

      expect(next).toEqual([city, condition('phone_number', 'is_present', '')]);
    });
  });

  describe('clearQuickFilter', () => {
    it('removes only the conditions the pill owns', () => {
      const conditions = [
        condition('email', 'is_present', ''),
        city,
        condition('phone_number', 'is_present', ''),
      ];

      expect(clearQuickFilter(conditions, QUICK_FILTER.CONTACT_METHOD)).toEqual(
        [city]
      );
    });

    it('returns an empty list when the pill held the only condition', () => {
      const conditions = setQuickFilter([], QUICK_FILTER.COUNTRY, 'TW');

      expect(clearQuickFilter(conditions, QUICK_FILTER.COUNTRY)).toEqual([]);
    });
  });

  describe('normalizeQueryOperators', () => {
    it('gives every condition an operator and resets the trailing one', () => {
      const conditions = [
        { ...name, queryOperator: undefined },
        { ...city, queryOperator: 'or' },
        { ...name, queryOperator: 'or' },
      ];

      expect(
        normalizeQueryOperators(conditions).map(item => item.queryOperator)
      ).toEqual(['and', 'or', 'and']);
    });
  });

  describe('hasOrJoin', () => {
    it('detects an OR between conditions', () => {
      expect(hasOrJoin([{ ...name, queryOperator: 'or' }, city])).toBe(true);
    });

    it('ignores the operator on the last condition, which joins nothing', () => {
      expect(hasOrJoin([name, { ...city, queryOperator: 'or' }])).toBe(false);
      expect(hasOrJoin([])).toBe(false);
    });
  });

  describe('last activity presets', () => {
    it.each([
      [1, '2026-09-29', 'TODAY'],
      [7, '2026-09-23', 'LAST_7_DAYS'],
      [30, '2026-08-31', 'LAST_30_DAYS'],
      [90, '2026-07-02', 'LAST_90_DAYS'],
    ])('maps %i days to %s (%s)', (days, date, key) => {
      expect(daysAgo(days, TODAY)).toBe(date);
      expect(lastActivityPreset(date, TODAY).key).toBe(key);
    });

    it('reads any other date as a custom date', () => {
      expect(lastActivityPreset('2026-09-01', TODAY)).toBeUndefined();
    });
  });
});
