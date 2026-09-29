<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { dynamicTime } from 'shared/helpers/timeHelper';

import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import LabelChip from 'dashboard/components-next/label/Label.vue';
import ContactsTableCrmCell from './ContactsTableCrmCell.vue';
import ContactsTableColumnsMenu from './ContactsTableColumnsMenu.vue';
import { CRM_ATTRIBUTE, findCrmStatusDefinition } from '../crmAttributes';
import {
  activityToneClass,
  customAttributeCell,
  isUnknownName,
  sourceIcon,
} from './contactsTable';

const props = defineProps({
  // camelCased contacts (contacts/getContactsList); custom_attributes keep their raw keys.
  contacts: { type: Array, required: true },
  selectedContactIds: { type: Array, default: () => [] },
  activeSort: { type: String, default: '' },
  activeOrdering: { type: String, default: '' },
});

// update:sort drives the same sort state as ContactSortMenu.
const emit = defineEmits(['toggleContact', 'toggleAll', 'update:sort']);

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const { uiSettings, updateUISettings } = useUISettings();

const labels = useMapGetter('labels/getLabels');
const attributeDefinitions = useMapGetter('attributes/getContactAttributes');

const EXTRA_COLUMNS_SETTING = 'contacts_table_extra_columns';
const MAX_LABEL_CHIPS = 2;
// Hidden below md, where only name, contact and CRM stay.
const WIDE_ONLY = 'hidden md:table-cell';
const CELL = 'h-9 px-3 whitespace-nowrap';

const crmStatusDefinition = computed(() =>
  findCrmStatusDefinition(attributeDefinitions.value)
);

const columns = computed(() =>
  [
    {
      key: 'name',
      label: t('CONTACTS_LAYOUT.TABLE.COLUMNS.NAME'),
      sort: 'name',
    },
    {
      key: 'company',
      label: t('CONTACTS_LAYOUT.TABLE.COLUMNS.COMPANY'),
      sort: 'company_name',
      wideOnly: true,
    },
    {
      key: 'contact',
      label: t('CONTACTS_LAYOUT.TABLE.COLUMNS.CONTACT'),
      sort: 'email',
    },
    {
      key: 'source',
      label: t('CONTACTS_LAYOUT.TABLE.COLUMNS.SOURCE'),
      wideOnly: true,
    },
    {
      key: 'labels',
      label: t('CONTACTS_LAYOUT.TABLE.COLUMNS.LABELS'),
      wideOnly: true,
    },
    {
      key: 'crm',
      label: t('CONTACTS_LAYOUT.TABLE.COLUMNS.CRM'),
      crmOnly: true,
    },
    {
      key: 'lastActivity',
      label: t('CONTACTS_LAYOUT.TABLE.COLUMNS.LAST_ACTIVITY'),
      sort: 'last_activity_at',
      wideOnly: true,
    },
  ].filter(column => !column.crmOnly || crmStatusDefinition.value)
);

const extraColumnKeys = computed({
  get: () => uiSettings.value?.[EXTRA_COLUMNS_SETTING] ?? [],
  set: keys => updateUISettings({ [EXTRA_COLUMNS_SETTING]: keys }),
});

// Keys whose definition was deleted since they were picked are skipped.
const extraColumns = computed(() =>
  extraColumnKeys.value
    .map(key =>
      attributeDefinitions.value.find(
        definition => definition.attributeKey === key
      )
    )
    .filter(Boolean)
);

const sortOrderOf = column =>
  props.activeSort === column.sort ? props.activeOrdering || 'asc' : null;

const ARIA_SORT = { asc: 'ascending', '-': 'descending' };
const SORT_ICON = { asc: 'i-lucide-arrow-up', '-': 'i-lucide-arrow-down' };

const sortBy = column => {
  const isAscending =
    props.activeSort === column.sort && props.activeOrdering === '';
  emit('update:sort', { sort: column.sort, order: isAscending ? '-' : '' });
};

const selectedIds = computed(() => new Set(props.selectedContactIds));
const selectedOnPage = computed(
  () =>
    props.contacts.filter(contact => selectedIds.value.has(contact.id)).length
);
const allSelected = computed(
  () =>
    props.contacts.length > 0 && selectedOnPage.value === props.contacts.length
);

const labelsByTitle = computed(
  () => new Map(labels.value.map(label => [label.title, label]))
);

const booleanLabels = computed(() => ({
  yes: t('FILTER.ATTRIBUTE_LABELS.TRUE'),
  no: t('FILTER.ATTRIBUTE_LABELS.FALSE'),
}));

const labelsCell = (titles = []) => ({
  chips: titles
    .slice(0, MAX_LABEL_CHIPS)
    .map(title => labelsByTitle.value.get(title) ?? title),
  hidden: Math.max(titles.length - MAX_LABEL_CHIPS, 0),
});

const companyCell = contact => {
  const company = contact.additionalAttributes?.companyName;
  const jobTitle = contact.customAttributes?.[CRM_ATTRIBUTE.JOB_TITLE];
  if (!jobTitle) return { company };
  return {
    company,
    jobTitle: company
      ? t('CONTACTS_LAYOUT.TABLE.JOB_TITLE', { title: jobTitle })
      : jobTitle,
  };
};

const toRow = contact => ({
  contact,
  name: contact.name || contact.email || contact.phoneNumber,
  isUnknown: isUnknownName(contact),
  ...companyCell(contact),
  reach: contact.email || contact.phoneNumber,
  reachIcon: contact.email ? 'i-lucide-mail' : 'i-lucide-phone',
  labels: labelsCell(contact.labels),
  activity: contact.lastActivityAt && {
    text: dynamicTime(contact.lastActivityAt),
    tone: activityToneClass(contact.lastActivityAt),
  },
  extras: extraColumns.value.map(definition => ({
    key: definition.attributeKey,
    ...customAttributeCell(
      definition.attributeDisplayType,
      contact.customAttributes?.[definition.attributeKey],
      booleanLabels.value
    ),
  })),
});

const rows = computed(() => props.contacts.map(toRow));

const DETAIL_ROUTES = {
  contacts_dashboard_segments_index: ['contacts_edit_segment', 'segmentId'],
  contacts_dashboard_labels_index: ['contacts_edit_label', 'label'],
};

const openContact = id => {
  const [name, paramKey] = DETAIL_ROUTES[route.name] || ['contacts_edit'];
  const params = {
    contactId: id,
    ...(paramKey && { [paramKey]: route.params[paramKey] }),
  };
  router.push({ name, params, query: route.query });
};
</script>

<template>
  <div class="w-full min-w-0 overflow-x-auto">
    <table class="w-full text-body-main text-n-slate-12">
      <thead>
        <tr class="border-b border-n-weak text-label-small text-n-slate-11">
          <th class="w-10 p-0">
            <label class="flex items-center h-9 px-3 cursor-pointer">
              <Checkbox
                :model-value="allSelected"
                :indeterminate="selectedOnPage > 0 && !allSelected"
                @change="event => emit('toggleAll', event.target.checked)"
              />
            </label>
          </th>
          <th
            v-for="column in columns"
            :key="column.key"
            :aria-sort="ARIA_SORT[sortOrderOf(column)]"
            class="font-medium text-start"
            :class="[CELL, column.wideOnly && WIDE_ONLY]"
          >
            <button
              v-if="column.sort"
              type="button"
              class="inline-flex items-center gap-1 hover:text-n-slate-12"
              :class="{ 'text-n-slate-12': sortOrderOf(column) }"
              @click="sortBy(column)"
            >
              {{ column.label }}
              <span
                v-if="sortOrderOf(column)"
                class="size-3"
                :class="SORT_ICON[sortOrderOf(column)]"
              />
            </button>
            <template v-else>
              {{ column.label }}
            </template>
          </th>
          <th
            v-for="definition in extraColumns"
            :key="definition.attributeKey"
            class="font-medium text-start"
            :class="[CELL, WIDE_ONLY]"
          >
            {{ definition.attributeDisplayName }}
          </th>
          <th class="px-1 text-end" :class="WIDE_ONLY">
            <ContactsTableColumnsMenu
              v-model="extraColumnKeys"
              :definitions="attributeDefinitions"
            />
          </th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="row in rows"
          :key="row.contact.id"
          data-test="contact-row"
          tabindex="0"
          class="border-b border-n-weak cursor-pointer hover:bg-n-alpha-1 focus-visible:bg-n-alpha-1 focus-visible:outline-none"
          :class="{ 'bg-n-alpha-2': selectedIds.has(row.contact.id) }"
          @click="openContact(row.contact.id)"
          @keydown.enter.self="openContact(row.contact.id)"
        >
          <td class="p-0" @click.stop>
            <label class="flex items-center h-9 px-3 cursor-pointer">
              <Checkbox
                :model-value="selectedIds.has(row.contact.id)"
                @change="
                  event =>
                    emit('toggleContact', {
                      id: row.contact.id,
                      value: event.target.checked,
                    })
                "
              />
            </label>
          </td>
          <td :class="CELL">
            <span
              data-test="contact-name"
              class="block max-w-[14rem] truncate text-heading-3"
              :class="{ 'text-n-slate-10': row.isUnknown }"
            >
              {{ row.name }}
            </span>
          </td>
          <td :class="[CELL, WIDE_ONLY]">
            <span class="flex items-center gap-1 max-w-[16rem] min-w-0">
              <span v-if="row.company" class="truncate">{{ row.company }}</span>
              <span v-if="row.jobTitle" class="truncate text-n-slate-11">
                {{ row.jobTitle }}
              </span>
            </span>
          </td>
          <td :class="CELL">
            <span
              v-if="row.reach"
              class="flex items-center gap-1.5 max-w-[16rem] text-n-slate-11"
            >
              <span class="size-3.5 shrink-0" :class="row.reachIcon" />
              <span class="truncate">{{ row.reach }}</span>
            </span>
          </td>
          <td :class="[CELL, WIDE_ONLY]">
            <span
              v-if="row.contact.sourceInbox"
              class="flex items-center gap-1.5 max-w-[10rem] text-n-slate-11"
            >
              <span
                data-test="source-icon"
                class="size-3.5 shrink-0"
                :class="sourceIcon(row.contact.sourceInbox.channelType)"
              />
              <span class="truncate">{{ row.contact.sourceInbox.name }}</span>
            </span>
          </td>
          <td :class="[CELL, WIDE_ONLY]">
            <span class="flex items-center gap-1">
              <LabelChip
                v-for="label in row.labels.chips"
                :key="label.title ?? label"
                compact
                :label="label"
              />
              <span
                v-if="row.labels.hidden"
                class="text-label-small text-n-slate-11"
              >
                {{
                  t('CONTACTS_LAYOUT.TABLE.MORE_LABELS', {
                    count: row.labels.hidden,
                  })
                }}
              </span>
            </span>
          </td>
          <td v-if="crmStatusDefinition" class="p-0">
            <ContactsTableCrmCell
              :attributes="row.contact.customAttributes"
              :status-definition="crmStatusDefinition"
            />
          </td>
          <td
            data-test="last-activity"
            class="tabular-nums"
            :class="[CELL, WIDE_ONLY, row.activity?.tone]"
          >
            {{ row.activity?.text }}
          </td>
          <td
            v-for="extra in row.extras"
            :key="extra.key"
            :class="[CELL, WIDE_ONLY]"
          >
            <a
              v-if="extra.href"
              :href="extra.href"
              target="_blank"
              rel="noopener noreferrer"
              class="block max-w-[14rem] truncate text-n-blue-11 hover:underline"
              @click.stop
            >
              {{ extra.text }}
            </a>
            <span v-else class="block max-w-[14rem] truncate text-n-slate-11">
              {{ extra.text }}
            </span>
          </td>
          <td :class="WIDE_ONLY" />
        </tr>
      </tbody>
    </table>
  </div>
</template>
