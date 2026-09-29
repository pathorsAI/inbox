/* global axios */

import ApiClient from '../ApiClient';

// Sync log and match-all backfill, shared by every CRM hook.
class CrmSyncAPI extends ApiClient {
  constructor() {
    super('integrations/hooks', { accountScoped: true });
  }

  getEvents(hookId, { page, status } = {}) {
    return axios.get(`${this.url}/${hookId}/sync_events`, {
      params: { page, status },
    });
  }

  getBackfill(hookId) {
    return axios.get(`${this.url}/${hookId}/crm_backfill`);
  }

  startBackfill(hookId) {
    return axios.post(`${this.url}/${hookId}/crm_backfill`);
  }
}

export default new CrmSyncAPI();
