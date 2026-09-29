<script setup>
import { ref, computed, unref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  useStore,
  useMapGetter,
  useFunctionGetter,
} from 'dashboard/composables/store';
import { useRouter } from 'vue-router';
import { breakpointsTailwind, useBreakpoints } from '@vueuse/core';
import { useAlert, useTrack } from 'dashboard/composables';
import { CONTACTS_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';
import filterQueryGenerator from 'dashboard/helper/filterQueryGenerator';
import contactFilterItems from 'dashboard/routes/dashboard/contacts/contactFilterItems';
import {
  DuplicateContactException,
  ExceptionWithMessage,
} from 'shared/helpers/CustomErrors';
import { generateValuesForEditCustomViews } from 'dashboard/helper/customViewsHelper';
import countries from 'shared/constants/countries';
import {
  useCamelCase,
  useSnakeCase,
} from 'dashboard/composables/useTransformKeys';

import ContactsHeader from 'dashboard/components-next/Contacts/ContactsHeader/ContactHeader.vue';
import ContactsFilterBar from 'dashboard/components-next/Contacts/ContactsHeader/components/ContactsFilterBar.vue';
import CreateNewContactDialog from 'dashboard/components-next/Contacts/ContactsForm/CreateNewContactDialog.vue';
import ContactExportDialog from 'dashboard/components-next/Contacts/ContactsForm/ContactExportDialog.vue';
import ContactImportDialog from 'dashboard/components-next/Contacts/ContactsForm/ContactImportDialog.vue';
import CreateSegmentDialog from 'dashboard/components-next/Contacts/ContactsForm/CreateSegmentDialog.vue';
import DeleteSegmentDialog from 'dashboard/components-next/Contacts/ContactsForm/DeleteSegmentDialog.vue';
import ContactsFilter from 'dashboard/components-next/filter/ContactsFilter.vue';

const props = defineProps({
  showSearch: { type: Boolean, default: true },
  searchValue: { type: String, default: '' },
  activeSort: { type: String, default: 'last_activity_at' },
  activeOrdering: { type: String, default: '' },
  headerTitle: { type: String, default: '' },
  segmentsId: { type: [String, Number], default: 0 },
  activeSegment: { type: Object, default: null },
  hasAppliedFilters: { type: Boolean, default: false },
  isLabelView: { type: Boolean, default: false },
  isActiveView: { type: Boolean, default: false },
});

const emit = defineEmits([
  'update:sort',
  'search',
  'applyFilter',
  'clearFilters',
]);

const { t } = useI18n();
const store = useStore();
const router = useRouter();

const contactsHeaderRef = ref(null);
const createNewContactDialogRef = ref(null);
const contactExportDialogRef = ref(null);
const contactImportDialogRef = ref(null);
const createSegmentDialogRef = ref(null);
const deleteSegmentDialogRef = ref(null);

// Draft edited in the advanced panel; the applied filters live in the store.
const appliedFilter = ref([]);
const segmentsQuery = ref({});

const appliedFilters = useMapGetter('contacts/getAppliedContactFiltersV4');
const contactAttributes = useMapGetter('attributes/getContactAttributes');
const labels = useMapGetter('labels/getLabels');
const twentyIntegration = useFunctionGetter(
  'integrations/getIntegration',
  'twenty'
);
const hasActiveSegments = computed(
  () => props.activeSegment && props.segmentsId !== 0
);
const activeSegmentName = computed(() => props.activeSegment?.name);
// Segment, label and active views keep their own filtering.
// Below sm the header wraps onto two rows; the collapsed filter buttons sit
// in its action row instead of taking a third.
const isBelowSm = useBreakpoints(breakpointsTailwind).smaller('sm');

const isListView = computed(
  () => !props.segmentsId && !props.isLabelView && !props.isActiveView
);

onMounted(() => store.dispatch('integrations/get'));

const openCreateNewContactDialog = () => {
  createNewContactDialogRef.value?.dialogRef.open();
};
const openContactImportDialog = () =>
  contactImportDialogRef.value?.dialogRef.open();
const openContactExportDialog = () =>
  contactExportDialogRef.value?.dialogRef.open();
const openCreateSegmentDialog = () =>
  createSegmentDialogRef.value?.dialogRef.open();
const openDeleteSegmentDialog = () =>
  deleteSegmentDialogRef.value?.dialogRef.open();

const onCreate = async contact => {
  try {
    await store.dispatch('contacts/create', contact);
    createNewContactDialogRef.value?.onSuccess();
    useAlert(
      t('CONTACTS_LAYOUT.HEADER.ACTIONS.CONTACT_CREATION.SUCCESS_MESSAGE')
    );
  } catch (error) {
    const i18nPrefix = 'CONTACTS_LAYOUT.HEADER.ACTIONS.CONTACT_CREATION';
    if (error instanceof DuplicateContactException) {
      if (error.data.includes('email')) {
        useAlert(t(`${i18nPrefix}.EMAIL_ADDRESS_DUPLICATE`));
      } else if (error.data.includes('phone_number')) {
        useAlert(t(`${i18nPrefix}.PHONE_NUMBER_DUPLICATE`));
      }
    } else if (error instanceof ExceptionWithMessage) {
      useAlert(error.data);
    } else {
      useAlert(t(`${i18nPrefix}.ERROR_MESSAGE`));
    }
  }
};

const onImport = async file => {
  try {
    await store.dispatch('contacts/import', file);
    contactImportDialogRef.value?.dialogRef.close();
    useAlert(
      t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.SUCCESS_MESSAGE')
    );
    useTrack(CONTACTS_EVENTS.IMPORT_SUCCESS);
  } catch (error) {
    useAlert(
      error.message ??
        t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.ERROR_MESSAGE')
    );
    useTrack(CONTACTS_EVENTS.IMPORT_FAILURE);
  }
};

const onExport = async query => {
  try {
    await store.dispatch('contacts/export', query);
    useAlert(
      t('CONTACTS_LAYOUT.HEADER.ACTIONS.EXPORT_CONTACT.SUCCESS_MESSAGE')
    );
  } catch (error) {
    useAlert(
      error.message ||
        t('CONTACTS_LAYOUT.HEADER.ACTIONS.EXPORT_CONTACT.ERROR_MESSAGE')
    );
  }
};

const onCreateSegment = async payload => {
  try {
    const payloadData = {
      ...payload,
      query: segmentsQuery.value,
    };
    const response = await store.dispatch('customViews/create', payloadData);
    createSegmentDialogRef.value?.dialogRef.close();
    useAlert(
      t('CONTACTS_LAYOUT.HEADER.ACTIONS.FILTERS.CREATE_SEGMENT.SUCCESS_MESSAGE')
    );
    const segmentId = response?.data?.id;
    if (!segmentId) return;
    // Navigate to the created segment
    router.push({
      name: 'contacts_dashboard_segments_index',
      params: { segmentId },
      query: { page: 1 },
    });
  } catch {
    useAlert(
      t('CONTACTS_LAYOUT.HEADER.ACTIONS.FILTERS.CREATE_SEGMENT.ERROR_MESSAGE')
    );
  }
};

const onDeleteSegment = async payload => {
  try {
    await store.dispatch('customViews/delete', {
      id: Number(props.segmentsId),
      ...payload,
    });
    router.push({
      name: 'contacts_dashboard_index',
      query: {
        page: 1,
      },
    });
    deleteSegmentDialogRef.value?.dialogRef.close();
    useAlert(
      t('CONTACTS_LAYOUT.HEADER.ACTIONS.FILTERS.DELETE_SEGMENT.SUCCESS_MESSAGE')
    );
  } catch (error) {
    useAlert(
      t('CONTACTS_LAYOUT.HEADER.ACTIONS.FILTERS.DELETE_SEGMENT.ERROR_MESSAGE')
    );
  }
};

const clearFilters = async () => {
  emit('clearFilters');
};

const onApplyFilter = async payload => {
  payload = useSnakeCase(payload);
  segmentsQuery.value = filterQueryGenerator(payload);
  emit('applyFilter', filterQueryGenerator(payload));
};

// The filter bar applies through the same store + refetch path as the advanced panel.
const applyConditions = conditions => {
  if (!conditions.length) {
    clearFilters();
    return;
  }
  store.dispatch(
    'contacts/setContactFilters',
    useSnakeCase(JSON.parse(JSON.stringify(conditions)))
  );
  onApplyFilter(conditions);
};

const applyAdvancedFilters = (filters, hide) => {
  onApplyFilter(filters);
  hide();
};

const onUpdateSegment = async (payload, segmentName, hide) => {
  payload = useSnakeCase(payload);
  const payloadData = {
    ...props.activeSegment,
    name: segmentName,
    query: filterQueryGenerator(payload),
  };
  await store.dispatch('customViews/update', payloadData);
  hide();
};

const setParamsForEditSegmentModal = () => {
  return {
    countries,
    filterTypes: contactFilterItems,
    allCustomAttributes: useSnakeCase(contactAttributes.value),
    labels: labels.value || [],
  };
};

const initializeSegmentToFilterModal = segment => {
  const query = unref(segment)?.query?.payload;
  if (!Array.isArray(query)) return;

  const newFilters = query.map(filter => {
    const transformed = useCamelCase(filter);
    const values = Array.isArray(transformed.values)
      ? generateValuesForEditCustomViews(
          useSnakeCase(filter),
          setParamsForEditSegmentModal()
        )
      : [];

    return {
      attributeKey: transformed.attributeKey,
      attributeModel: transformed.attributeModel,
      customAttributeType: transformed.customAttributeType,
      filterOperator: transformed.filterOperator,
      queryOperator: transformed.queryOperator ?? 'and',
      values,
    };
  });

  appliedFilter.value = [...appliedFilter.value, ...newFilters];
};

// Loads the applied filters, or the segment's, into the advanced panel as it opens.
const prepareFilterDraft = () => {
  appliedFilter.value = [];
  if (hasActiveSegments.value) {
    initializeSegmentToFilterModal(props.activeSegment);
  } else {
    appliedFilter.value = props.hasAppliedFilters
      ? [...appliedFilters.value]
      : [
          {
            attributeKey: 'name',
            filterOperator: 'equal_to',
            values: '',
            queryOperator: 'and',
            attributeModel: 'standard',
          },
        ];
  }
};

defineExpose({
  openSegmentFilter: () => contactsHeaderRef.value.openSegmentFilter(),
});
</script>

<template>
  <ContactsHeader
    ref="contactsHeaderRef"
    :show-search="showSearch"
    :search-value="searchValue"
    :active-sort="activeSort"
    :active-ordering="activeOrdering"
    :header-title="headerTitle"
    :is-segments-view="hasActiveSegments"
    :is-label-view="isLabelView"
    :is-active-view="isActiveView"
    :button-label="t('CONTACTS_LAYOUT.HEADER.MESSAGE_BUTTON')"
    @search="emit('search', $event)"
    @update:sort="emit('update:sort', $event)"
    @add="openCreateNewContactDialog"
    @import="openContactImportDialog"
    @export="openContactExportDialog"
    @filter="prepareFilterDraft"
    @delete-segment="openDeleteSegmentDialog"
  >
    <template v-if="isListView && isBelowSm" #leading>
      <ContactsFilterBar
        compact
        :filters="appliedFilters"
        :labels="labels"
        :show-twenty="!!twentyIntegration.enabled"
        @apply="applyConditions"
        @open-advanced="prepareFilterDraft"
        @create-segment="openCreateSegmentDialog"
        @clear-all="clearFilters"
      >
        <template #advanced="{ hide }">
          <ContactsFilter
            v-model="appliedFilter"
            @apply-filter="filters => applyAdvancedFilters(filters, hide)"
            @clear-filters="clearFilters"
          />
        </template>
      </ContactsFilterBar>
    </template>
    <template #filter="{ hide }">
      <ContactsFilter
        v-model="appliedFilter"
        :segment-name="activeSegmentName"
        is-segment-view
        @update-segment="
          (filters, name) => onUpdateSegment(filters, name, hide)
        "
        @clear-filters="clearFilters"
      />
    </template>
  </ContactsHeader>

  <div v-if="isListView && !isBelowSm" class="px-6 pb-2">
    <ContactsFilterBar
      class="w-full mx-auto max-w-5xl"
      :filters="appliedFilters"
      :labels="labels"
      :show-twenty="!!twentyIntegration.enabled"
      @apply="applyConditions"
      @open-advanced="prepareFilterDraft"
      @create-segment="openCreateSegmentDialog"
      @clear-all="clearFilters"
    >
      <template #advanced="{ hide }">
        <ContactsFilter
          v-model="appliedFilter"
          @apply-filter="filters => applyAdvancedFilters(filters, hide)"
          @clear-filters="clearFilters"
        />
      </template>
    </ContactsFilterBar>
  </div>

  <CreateNewContactDialog ref="createNewContactDialogRef" @create="onCreate" />
  <ContactExportDialog ref="contactExportDialogRef" @export="onExport" />
  <ContactImportDialog ref="contactImportDialogRef" @import="onImport" />
  <CreateSegmentDialog ref="createSegmentDialogRef" @create="onCreateSegment" />
  <DeleteSegmentDialog ref="deleteSegmentDialogRef" @delete="onDeleteSegment" />
</template>
