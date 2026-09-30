import { validateAuthenticateRoutePermission } from './index';
import store from '../store'; // This import will be mocked
import { vi } from 'vitest';

// Mock the store module
vi.mock('../store', () => ({
  default: {
    getters: {
      isLoggedIn: false,
      getCurrentUser: {
        account_id: null,
        id: null,
        accounts: [],
      },
      'accounts/getAccount': () => ({}),
    },
    dispatch: vi.fn(() => Promise.resolve()),
  },
}));

describe('#validateAuthenticateRoutePermission', () => {
  let next;

  beforeEach(() => {
    next = vi.fn(); // Mock the next function
    window.sessionStorage.clear();
  });

  describe('when user is not logged in', () => {
    it('should redirect to login', () => {
      const to = { name: 'some-protected-route', params: { accountId: 1 } };

      // Mock the store to simulate user not logged in
      store.getters.isLoggedIn = false;

      // Mock window.location.assign
      const mockAssign = vi.fn();
      delete window.location;
      window.location = { assign: mockAssign };

      validateAuthenticateRoutePermission(to, next);

      expect(mockAssign).toHaveBeenCalledWith('/app/login');
      expect(window.sessionStorage.getItem('loginReturnPath')).toBeNull();
    });

    it('remembers a route that resumes after login', () => {
      const to = {
        name: 'pathors_connect',
        fullPath: '/app/pathors/connect?organization_id=org-1',
        params: {},
        meta: { accountAgnostic: true, resumeAfterLogin: true },
      };
      store.getters.isLoggedIn = false;
      const mockAssign = vi.fn();
      delete window.location;
      window.location = { assign: mockAssign };

      validateAuthenticateRoutePermission(to, next);

      expect(mockAssign).toHaveBeenCalledWith('/app/login');
      expect(window.sessionStorage.getItem('loginReturnPath')).toBe(
        '/app/pathors/connect?organization_id=org-1'
      );
    });
  });

  describe('when a route was remembered before login', () => {
    beforeEach(() => {
      store.getters.isLoggedIn = true;
      store.getters.getCurrentUser = { account_id: null, id: 1, accounts: [] };
      window.sessionStorage.setItem(
        'loginReturnPath',
        '/app/pathors/connect?organization_id=org-1'
      );
    });

    it('resumes it once, instead of the landing route', async () => {
      const to = { name: 'no_accounts', fullPath: '/app/no-accounts' };

      await validateAuthenticateRoutePermission(to, next);

      expect(next).toHaveBeenCalledWith(
        '/app/pathors/connect?organization_id=org-1'
      );
      expect(window.sessionStorage.getItem('loginReturnPath')).toBeNull();
    });

    it('lets an account-agnostic route through for a user without accounts', async () => {
      const to = {
        name: 'pathors_connect',
        fullPath: '/app/pathors/connect?organization_id=org-1',
        params: {},
        meta: { accountAgnostic: true, resumeAfterLogin: true },
      };

      await validateAuthenticateRoutePermission(to, next);

      expect(next).toHaveBeenCalledWith();
      expect(window.sessionStorage.getItem('loginReturnPath')).toBeNull();
    });
  });

  describe('when user is logged in', () => {
    beforeEach(() => {
      // Mock the store's getter for a logged-in user
      store.getters.isLoggedIn = true;
      store.getters.getCurrentUser = {
        account_id: 1,
        id: 1,
        accounts: [
          {
            id: 1,
            role: 'agent',
            permissions: ['agent'],
            status: 'active',
          },
        ],
      };
    });

    describe('when route is not accessible to current user', () => {
      it('should redirect to dashboard', async () => {
        const to = {
          name: 'general_settings_index',
          params: { accountId: 1 },
          meta: { permissions: ['administrator'] },
        };

        await validateAuthenticateRoutePermission(to, next);

        expect(next).toHaveBeenCalledWith('/app/accounts/1/dashboard');
      });
    });

    describe('when route is accessible to current user', () => {
      beforeEach(() => {
        // Adjust store getters to reflect the user has admin permissions
        store.getters.getCurrentUser = {
          account_id: 1,
          id: 1,
          accounts: [
            {
              id: 1,
              role: 'administrator',
              permissions: ['administrator'],
              status: 'active',
            },
          ],
        };
      });

      it('should go to the intended route', async () => {
        const to = {
          name: 'general_settings_index',
          params: { accountId: 1 },
          meta: { permissions: ['administrator'] },
        };

        await validateAuthenticateRoutePermission(to, next);

        expect(next).toHaveBeenCalledWith();
      });
    });
  });
});
