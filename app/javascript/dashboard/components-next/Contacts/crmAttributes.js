/**
 * The contact custom attributes any CRM integration writes (crm_*). Nothing here knows which CRM
 * wrote them: the list, its CRM column and the CRM quick filter read only these keys.
 */
export const CRM_ATTRIBUTE = {
  STATUS: 'crm_status',
  PROVIDER: 'crm_provider',
  JOB_TITLE: 'crm_job_title',
  STAGE: 'crm_stage',
  OPPORTUNITY: 'crm_opportunity',
  OWNER: 'crm_owner',
  URL: 'crm_url',
};

// crm_status stores the account-localized label found at this index of the definition's
// attribute_values, so the state is read back by position, never by comparing the label.
export const CRM_STATUS = ['linked', 'needs_attention', 'unlinked'];

/** The crm_status definition among the camelCased contact attribute definitions, if any. */
export const findCrmStatusDefinition = definitions =>
  definitions.find(
    definition => definition.attributeKey === CRM_ATTRIBUTE.STATUS
  );

/** 'linked' | 'needs_attention' | 'unlinked', or null for a missing or unknown value. */
export const crmStatusOf = (definition, value) =>
  CRM_STATUS[definition?.attributeValues?.indexOf(value)] ?? null;
