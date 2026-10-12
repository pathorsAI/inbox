import {
  CONVERSATION_PERMISSIONS,
  ROLES,
} from 'dashboard/constants/permissions';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { CALL_VIEWS } from 'dashboard/components-next/Calls/constants';
import { frontendURL } from '../../../helper/URLHelper';
import CallsIndex from './pages/CallsIndex.vue';

const meta = {
  permissions: [...ROLES, ...CONVERSATION_PERMISSIONS],
  featureFlag: FEATURE_FLAGS.CHANNEL_VOICE,
};

// Every view has its own route rather than a query variant of one: the sidebar
// marks the active item by path, and `?call=<id>` (the open sheet) must not
// move it.
const viewRoute = (name, path, view) => ({
  path: frontendURL(`accounts/:accountId/calls/${path}`),
  name,
  component: CallsIndex,
  props: { view },
  meta,
});

export const routes = [
  {
    // Kept for existing links and the go-to hotkey.
    path: frontendURL('accounts/:accountId/calls'),
    name: 'calls_dashboard_index',
    redirect: to => ({
      name: 'calls_need',
      params: to.params,
      query: to.query,
    }),
    meta,
  },
  viewRoute('calls_need', 'need', CALL_VIEWS.NEED),
  viewRoute('calls_live', 'live', CALL_VIEWS.LIVE),
  viewRoute('calls_all', 'all', CALL_VIEWS.ALL),
  viewRoute('calls_mine', 'mine', CALL_VIEWS.MINE),
  {
    path: frontendURL('accounts/:accountId/calls/line/:inboxId'),
    name: 'calls_line',
    component: CallsIndex,
    props: route => ({
      view: CALL_VIEWS.LINE,
      inboxId: Number(route.params.inboxId),
    }),
    meta,
  },
];
