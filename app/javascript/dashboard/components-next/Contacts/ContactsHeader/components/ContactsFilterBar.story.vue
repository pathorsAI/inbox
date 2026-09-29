<script setup>
import { ref } from 'vue';
import ContactsFilterBar from './ContactsFilterBar.vue';
import { daysAgo } from './quickFilters/conditions';

const labels = ['newsletter', 'notification', 'vip', 'lead', 'churn-risk'].map(
  title => ({ title })
);

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
  condition('twenty_status', 'equal_to', { id: 'linked', name: 'linked' }),
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
        show-twenty
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
        show-twenty
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
        show-twenty
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
          show-twenty
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
