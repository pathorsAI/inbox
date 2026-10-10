/* global axios */

import ApiClient from '../ApiClient';

class GithubAPI extends ApiClient {
  constructor() {
    super('integrations/github', { accountScoped: true });
  }

  connect({ code, installationId, state }) {
    return axios.post(this.url, {
      code,
      installation_id: installationId,
      state,
    });
  }

  getRepositories() {
    return axios.get(`${this.url}/repositories`);
  }

  updateSettings({ repository, label }) {
    return axios.patch(this.url, { repository, label });
  }
}

export default new GithubAPI();
