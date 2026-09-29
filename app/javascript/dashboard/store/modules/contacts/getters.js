import camelcaseKeys from 'camelcase-keys';

export const getters = {
  getContacts($state) {
    return $state.sortOrder.map(contactId => $state.records[contactId]);
  },
  getContactsList($state) {
    const contacts = $state.sortOrder.map(
      contactId => $state.records[contactId]
    );
    // Custom attribute keys stay as defined, so they match their definitions' attribute_key.
    return camelcaseKeys(contacts, {
      deep: true,
      stopPaths: ['custom_attributes'],
    });
  },
  getUIFlags($state) {
    return $state.uiFlags;
  },
  getContact: $state => id => {
    const contact = $state.records[id];
    return contact || {};
  },
  getContactById: $state => id => {
    const contact = $state.records[id];
    return camelcaseKeys(contact || {}, {
      deep: true,
      stopPaths: ['custom_attributes'],
    });
  },
  getContactAttachments: $state => id => $state.records[id]?.attachments || [],
  getMeta: $state => {
    return $state.meta;
  },
  getAppliedContactFilters: _state => {
    return _state.appliedFilters;
  },
  getAppliedContactFiltersV4: _state => {
    return _state.appliedFilters.map(camelcaseKeys);
  },
};
