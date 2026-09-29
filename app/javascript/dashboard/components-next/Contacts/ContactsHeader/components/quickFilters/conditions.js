/**
 * The quick-filter pills are a view over the contact filter conditions kept in the store
 * (`contacts/getAppliedContactFiltersV4`). A pill owns the conditions matching its attribute and
 * operator; everything else belongs to the advanced panel. Conditions keep the advanced panel's
 * value shapes (a string, an option `{ id, name }` or a list of options), so either side can edit
 * what the other wrote, and `filterQueryGenerator` turns them into the request payload.
 */
import { format, subDays } from 'date-fns';
import countries from 'shared/constants/countries';
import { CRM_ATTRIBUTE } from 'dashboard/components-next/Contacts/crmAttributes';

// Each key doubles as its i18n group under CONTACTS_LAYOUT.FILTER.QUICK.
export const QUICK_FILTER = {
  LAST_ACTIVITY: 'LAST_ACTIVITY',
  LABELS: 'LABELS',
  COMPANY: 'COMPANY',
  COUNTRY: 'COUNTRY',
  CONTACT_METHOD: 'CONTACT_METHOD',
  CRM_STATUS: 'CRM_STATUS',
};

// Bar order is priority order: pills collapse into the overflow menu from the end.
export const QUICK_FILTER_ORDER = [
  QUICK_FILTER.LAST_ACTIVITY,
  QUICK_FILTER.LABELS,
  QUICK_FILTER.COMPANY,
  QUICK_FILTER.COUNTRY,
  QUICK_FILTER.CONTACT_METHOD,
  QUICK_FILTER.CRM_STATUS,
];

// "Today" is anything after yesterday.
export const LAST_ACTIVITY_PRESETS = [
  { key: 'TODAY', days: 1 },
  { key: 'LAST_7_DAYS', days: 7 },
  { key: 'LAST_30_DAYS', days: 30 },
  { key: 'LAST_90_DAYS', days: 90 },
];

export const CONTACT_METHOD = { EMAIL: 'EMAIL', PHONE: 'PHONE', BOTH: 'BOTH' };

const ATTRIBUTE = {
  LAST_ACTIVITY: 'last_activity_at',
  LABELS: 'labels',
  COMPANY: 'company_name',
  COUNTRY: 'country_code',
  EMAIL: 'email',
  PHONE: 'phone_number',
  CRM_STATUS: CRM_ATTRIBUTE.STATUS,
};

const patternOf = ({ attributeKey, filterOperator }) =>
  `${attributeKey}:${filterOperator}`;

const OWNED_PATTERNS = {
  [QUICK_FILTER.LAST_ACTIVITY]: new Set([
    `${ATTRIBUTE.LAST_ACTIVITY}:is_greater_than`,
  ]),
  [QUICK_FILTER.LABELS]: new Set([`${ATTRIBUTE.LABELS}:equal_to`]),
  [QUICK_FILTER.COMPANY]: new Set([`${ATTRIBUTE.COMPANY}:contains`]),
  [QUICK_FILTER.COUNTRY]: new Set([`${ATTRIBUTE.COUNTRY}:equal_to`]),
  [QUICK_FILTER.CONTACT_METHOD]: new Set([
    `${ATTRIBUTE.EMAIL}:is_present`,
    `${ATTRIBUTE.PHONE}:is_present`,
  ]),
  [QUICK_FILTER.CRM_STATUS]: new Set([`${ATTRIBUTE.CRM_STATUS}:equal_to`]),
};

export const ownsCondition = (pill, condition) =>
  OWNED_PATTERNS[pill].has(patternOf(condition));

export const toDateString = date => format(date, 'yyyy-MM-dd');

export const daysAgo = (days, today = new Date()) =>
  toDateString(subDays(today, days));

/** The preset whose cutoff is `date`, or undefined for a custom date. */
export const lastActivityPreset = (date, today = new Date()) =>
  LAST_ACTIVITY_PRESETS.find(({ days }) => daysAgo(days, today) === date);

export const countryName = code =>
  countries.find(country => country.id === code)?.name ?? code;

// A string, an option or a list of options, flattened to ids.
const valueIds = values =>
  [values]
    .flat()
    .filter(value => value !== '' && value != null)
    .map(value => value.id ?? value);

const firstId = conditions => valueIds(conditions[0].values)[0];

const readContactMethod = conditions => {
  const attributes = new Set(conditions.map(c => c.attributeKey));
  if (!attributes.has(ATTRIBUTE.PHONE)) return CONTACT_METHOD.EMAIL;
  if (!attributes.has(ATTRIBUTE.EMAIL)) return CONTACT_METHOD.PHONE;
  return CONTACT_METHOD.BOTH;
};

const READERS = {
  [QUICK_FILTER.LAST_ACTIVITY]: firstId,
  [QUICK_FILTER.LABELS]: conditions => valueIds(conditions[0].values),
  [QUICK_FILTER.COMPANY]: firstId,
  [QUICK_FILTER.COUNTRY]: firstId,
  [QUICK_FILTER.CONTACT_METHOD]: readContactMethod,
  [QUICK_FILTER.CRM_STATUS]: firstId,
};

const condition = (
  attributeKey,
  filterOperator,
  values,
  attributeModel = 'standard'
) => ({
  attributeKey,
  filterOperator,
  values,
  queryOperator: 'and',
  attributeModel,
});

const option = (id, name = id) => ({ id, name });

const presence = attributeKey => condition(attributeKey, 'is_present', '');

const buildContactMethod = method => {
  if (method === CONTACT_METHOD.EMAIL) return [presence(ATTRIBUTE.EMAIL)];
  if (method === CONTACT_METHOD.PHONE) return [presence(ATTRIBUTE.PHONE)];
  return [presence(ATTRIBUTE.EMAIL), presence(ATTRIBUTE.PHONE)];
};

const BUILDERS = {
  [QUICK_FILTER.LAST_ACTIVITY]: date => [
    condition(ATTRIBUTE.LAST_ACTIVITY, 'is_greater_than', date),
  ],
  [QUICK_FILTER.LABELS]: titles => [
    condition(
      ATTRIBUTE.LABELS,
      'equal_to',
      titles.map(title => option(title))
    ),
  ],
  [QUICK_FILTER.COMPANY]: text => [
    condition(ATTRIBUTE.COMPANY, 'contains', text),
  ],
  [QUICK_FILTER.COUNTRY]: code => [
    condition(ATTRIBUTE.COUNTRY, 'equal_to', option(code, countryName(code))),
  ],
  [QUICK_FILTER.CONTACT_METHOD]: buildContactMethod,
  // A contact custom attribute of the list type, shaped as the advanced panel keeps one.
  [QUICK_FILTER.CRM_STATUS]: status => [
    condition(
      ATTRIBUTE.CRM_STATUS,
      'equal_to',
      option(status),
      'customAttributes'
    ),
  ],
};

/**
 * Every condition carries a query operator, as the advanced panel keeps them. The last one joins
 * nothing, so it is reset to 'and' (a stale 'or' there would start joining once something is
 * appended); `filterQueryGenerator` drops it from the request.
 */
export const normalizeQueryOperators = conditions =>
  conditions.map((item, index) => ({
    ...item,
    queryOperator:
      index < conditions.length - 1 ? item.queryOperator || 'and' : 'and',
  }));

/**
 * The backend joins conditions in order without parentheses, so once any of them joins with OR
 * a pill cannot add or drop its own without changing what the OR groups.
 */
export const hasOrJoin = conditions =>
  conditions.slice(0, -1).some(item => item.queryOperator === 'or');

/**
 * Reads the pills out of a condition list.
 * @param {Object[]} conditions - Applied conditions, camelCased.
 * @param {string[]} pills - The pills on the bar; conditions of other pills count as advanced.
 * @returns {{ values: Record<string, any>, counts: Record<string, number>, advancedCount: number }}
 *   `values[pill]` is null when the pill is unset; `counts[pill]` is how many conditions it owns.
 */
export const readQuickFilters = (conditions, pills) => {
  const values = {};
  const counts = {};
  pills.forEach(pill => {
    const owned = conditions.filter(item => ownsCondition(pill, item));
    counts[pill] = owned.length;
    values[pill] = owned.length ? READERS[pill](owned) : null;
  });
  const advancedCount = conditions.filter(
    item => !pills.some(pill => ownsCondition(pill, item))
  ).length;
  return { values, counts, advancedCount };
};

/** Replaces the pill's conditions in place, or appends them when the pill was unset. */
export const setQuickFilter = (conditions, pill, value) => {
  const base = normalizeQueryOperators(conditions);
  const index = base.findIndex(item => ownsCondition(pill, item));
  const rest = base.filter(item => !ownsCondition(pill, item));
  const at = index === -1 ? rest.length : index;
  return normalizeQueryOperators([
    ...rest.slice(0, at),
    ...BUILDERS[pill](value),
    ...rest.slice(at),
  ]);
};

export const clearQuickFilter = (conditions, pill) =>
  normalizeQueryOperators(
    conditions.filter(item => !ownsCondition(pill, item))
  );
