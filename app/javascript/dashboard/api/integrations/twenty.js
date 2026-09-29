/* global axios */

import ApiClient from '../ApiClient';

class TwentyAPI extends ApiClient {
  constructor() {
    super('integrations/twenty', { accountScoped: true });
  }

  getPerson(contactId, { signal } = {}) {
    return axios.get(`${this.url}/person`, {
      params: { contact_id: contactId },
      signal,
    });
  }

  createPerson(contactId, { signal } = {}) {
    return axios.post(
      `${this.url}/person`,
      { contact_id: contactId },
      { signal }
    );
  }

  resolveConflict(payload, { signal } = {}) {
    return axios.post(`${this.url}/conflicts/resolve`, payload, { signal });
  }

  getConflicts(page = 1) {
    return axios.get(`${this.url}/conflicts`, { params: { page } });
  }
}

export default new TwentyAPI();
