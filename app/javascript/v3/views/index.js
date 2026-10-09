import { createRouter, createWebHistory } from 'vue-router';

import routes from './routes';
import AnalyticsHelper from 'dashboard/helper/AnalyticsHelper';
import { validateAuthRouteAccess } from '../helpers/RouteHelper';

export const router = createRouter({ history: createWebHistory(), routes });

const sensitiveRouteNames = ['auth_password_edit'];

export const initalizeRouter = () => {
  router.beforeEach((to, _, next) => {
    if (!sensitiveRouteNames.includes(to.name)) {
      AnalyticsHelper.page(to.name || '', {
        path: to.path,
        name: to.name,
      });
    }

    return validateAuthRouteAccess(to, next, globalThis.chatwootConfig);
  });
};

export default router;
