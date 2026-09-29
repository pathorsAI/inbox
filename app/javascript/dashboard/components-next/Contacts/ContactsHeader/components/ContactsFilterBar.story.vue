<script setup>
import { ref } from 'vue';
import ContactsFilterBar from './ContactsFilterBar.vue';
import { daysAgo } from './quickFilters/conditions';

const labels = ['newsletter', 'notification', 'vip', 'lead', 'churn-risk'].map(
  title => ({ title })
);

const crmStatuses = ['已連結', '需要處理', '未連結'];

const condition = (attributeKey, filterOperator, values, queryOperator) => ({
  attributeKey,
  filterOperator,
  values,
  queryOperator: queryOperator ?? 'and',
  attributeModel: 'standard',
});

const threePills = () => [
  condition('last_activity_at', 'is_greater_than', daysAgo(7)),
  condition('labels', 'equal_to', [
    { id: 'newsletter', name: 'newsletter' },
    { id: 'notification', name: 'notification' },
  ]),
  condition('crm_status', 'equal_to', { id: '已連結', name: '已連結' }),
  condition('city', 'contains', 'Taipei'),
];

const empty = ref([]);
const withPills = ref(threePills());
const withOr = ref([
  condition('name', 'equal_to', 'Anna', 'or'),
  condition('email', 'contains', 'acme.com'),
  condition('company_name', 'contains', 'Acme'),
]);
const narrow = ref(threePills());

const onCreateSegment = () => console.log('Save as segment');
</script>

<template>
  <Story
    title="Components/Contacts/ContactsFilterBar"
    :layout="{ type: 'grid', width: '1000px' }"
  >
    <Variant title="Nothing applied">
      <ContactsFilterBar
        :filters="empty"
        :labels="labels"
        :crm-statuses="crmStatuses"
        @apply="empty = $event"
        @clear-all="empty = []"
        @create-segment="onCreateSegment"
      >
        <template #advanced>
          <div class="p-6 w-96 text-n-slate-11">
            {{ $t('CONTACTS_LAYOUT.FILTER.TITLE') }}
          </div>
        </template>
      </ContactsFilterBar>
    </Variant>

    <Variant title="Three pills set, one advanced condition">
      <ContactsFilterBar
        :filters="withPills"
        :labels="labels"
        :crm-statuses="crmStatuses"
        @apply="withPills = $event"
        @clear-all="withPills = []"
        @create-segment="onCreateSegment"
      >
        <template #advanced>
          <div class="p-6 w-96 text-n-slate-11">
            {{ $t('CONTACTS_LAYOUT.FILTER.TITLE') }}
          </div>
        </template>
      </ContactsFilterBar>
    </Variant>

    <Variant title="Advanced conditions use OR">
      <ContactsFilterBar
        :filters="withOr"
        :labels="labels"
        :crm-statuses="crmStatuses"
        @apply="withOr = $event"
        @clear-all="withOr = []"
        @create-segment="onCreateSegment"
      >
        <template #advanced>
          <div class="p-6 w-96 text-n-slate-11">
            {{ $t('CONTACTS_LAYOUT.FILTER.TITLE') }}
          </div>
        </template>
      </ContactsFilterBar>
    </Variant>

    <Variant title="Narrow width">
      <div class="w-[520px]">
        <ContactsFilterBar
          :filters="narrow"
          :labels="labels"
          :crm-statuses="crmStatuses"
          @apply="narrow = $event"
          @clear-all="narrow = []"
          @create-segment="onCreateSegment"
        >
          <template #advanced>
            <div class="p-6 w-96 text-n-slate-11">
              {{ $t('CONTACTS_LAYOUT.FILTER.TITLE') }}
            </div>
          </template>
        </ContactsFilterBar>
      </div>
    </Variant>
  </Story>
</template>
