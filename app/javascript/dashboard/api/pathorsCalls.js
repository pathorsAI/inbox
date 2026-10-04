/* global axios */
import ApiClient from './ApiClient';

class PathorsCallsAPI extends ApiClient {
  constructor() {
    super('pathors/calls', { accountScoped: true });
  }

  // `accountId` is optional — ApiClient derives it from the route, but callers
  // that already hold it can pass it explicitly.
  memberUrl(callId, action, accountId) {
    return accountId
      ? `/api/v1/accounts/${accountId}/pathors/calls/${callId}/${action}`
      : `${this.url}/${callId}/${action}`;
  }

  // The relay hands back a LiveKit token for the room the Pathors voice agent
  // is already in.
  join(callId, accountId) {
    return axios
      .post(this.memberUrl(callId, 'join', accountId))
      .then(r => r.data);
  }

  // Ends the call for everyone (the voice agent tears the room down). Taking a
  // call over is final, so this is the agent's only way out of it.
  hangup(callId, accountId) {
    return axios
      .post(this.memberUrl(callId, 'hangup', accountId))
      .then(r => r.data);
  }

  // Live Pathors calls in the inboxes the viewer can open, for the pinned group
  // at the top of the conversation list.
  active() {
    return axios.get(`${this.url}/active`).then(r => r.data);
  }
}

export default new PathorsCallsAPI();
