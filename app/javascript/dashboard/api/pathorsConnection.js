/* global axios */
import ApiClient from './ApiClient';

// Pathors-initiated connect. Scoped to the signed-in user, not an account: the
// page picks which account to bind to the Pathors organization.
class PathorsConnectionAPI extends ApiClient {
  constructor() {
    super('pathors/connection');
  }

  connect({ accountId, organizationId }) {
    return axios.post(this.url, {
      account_id: accountId,
      organization_id: organizationId,
    });
  }

  createAccount({ accountName, organizationId }) {
    return axios.post(`${this.url}/accounts`, {
      account_name: accountName,
      organization_id: organizationId,
    });
  }
}

export default new PathorsConnectionAPI();
