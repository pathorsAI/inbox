import settings from './settings/settings.routes';
import conversation from './conversation/conversation.routes';
import { routes as searchRoutes } from '../../modules/search/search.routes';
import { routes as callRoutes } from './calls/routes';
import { routes as contactRoutes } from './contacts/routes';
import { routes as companyRoutes } from './companies/routes';
import { routes as ticketRoutes } from './tickets/routes';
import { routes as inboxRoutes } from './inbox/routes';
import { frontendURL } from '../../helper/URLHelper';
import helpcenterRoutes from './helpcenter/helpcenter.routes';
import campaignsRoutes from './campaigns/campaigns.routes';
import { routes as captainRoutes } from './captain/captain.routes';
import AppContainer from './Dashboard.vue';
import Suspended from './suspended/Index.vue';
import NoAccounts from './noAccounts/Index.vue';
import OnboardingAccountDetails from './onboarding/Index.vue';
import OnboardingInboxSetup from './onboarding/InboxSetup.vue';
import PathorsConnect from './pathorsConnect/Index.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId'),
      component: AppContainer,
      children: [
        ...captainRoutes,
        ...inboxRoutes,
        ...conversation.routes,
        ...settings.routes,
        ...callRoutes,
        ...contactRoutes,
        ...companyRoutes,
        ...ticketRoutes,
        ...searchRoutes,
        ...helpcenterRoutes.routes,
        ...campaignsRoutes.routes,
      ],
    },
    {
      path: frontendURL('accounts/:accountId/onboarding'),
      name: 'onboarding_account_details',
      meta: {
        permissions: ['administrator', 'agent', 'custom_role'],
      },
      component: OnboardingAccountDetails,
    },
    {
      path: frontendURL('accounts/:accountId/onboarding/inbox-setup'),
      name: 'onboarding_inbox_setup',
      meta: {
        permissions: ['administrator', 'agent', 'custom_role'],
      },
      component: OnboardingInboxSetup,
    },
    {
      path: frontendURL('accounts/:accountId/suspended'),
      name: 'account_suspended',
      meta: {
        permissions: ['administrator', 'agent', 'custom_role'],
      },
      component: Suspended,
    },
    {
      path: frontendURL('no-accounts'),
      name: 'no_accounts',
      component: NoAccounts,
    },
    // Entered from a Pathors organization page, before any account is chosen.
    {
      path: frontendURL('pathors/connect'),
      name: 'pathors_connect',
      meta: { accountAgnostic: true, resumeAfterLogin: true },
      component: PathorsConnect,
      props: route => ({ organizationId: route.query.organization_id ?? '' }),
    },
  ],
};
