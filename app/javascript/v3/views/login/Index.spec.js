import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import Login from './Index.vue';
import routes from '../routes';
import { getLoginRedirectURL } from '../../helpers/AuthHelper';
import { login } from '../../api/auth';

vi.mock('../../api/auth', () => ({
  login: vi.fn(),
}));

describe('login retries', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('preserves the Shopify pricing redirect after resolving a session limit', async () => {
    login.mockResolvedValue(null);
    const context = {
      email: '',
      credentials: {
        email: 'john@example.com',
        password: 'Password1!',
      },
      ssoAuthToken: '',
      ssoAccountId: '',
      ssoConversationId: '',
      redirectUrl:
        'settings/billing?plan_handle=growth&shop=store.myshopify.com',
      sessionsLimitReached: true,
      limitedSessions: [{ id: 1 }],
      loginApi: { showLoading: false, hasErrored: false },
      handleImpersonation: vi.fn(),
      showAlertMessage: vi.fn(),
      $t: key => key,
    };

    Login.methods.retryLoginWithParams.call(context, {
      revoke_session_id: 1,
    });
    await Promise.resolve();

    expect(login).toHaveBeenCalledWith(
      expect.objectContaining({
        redirectUrl:
          'settings/billing?plan_handle=growth&shop=store.myshopify.com',
        revoke_session_id: 1,
      })
    );
  });
});

describe('SAML login', () => {
  it('carries the pending Shopify install redirect to the SSO route', () => {
    const redirectUrl = `settings/integrations/shopify?shopify_pending_install=${'a'.repeat(32)}`;

    expect(Login.computed.samlLoginRoute.call({ redirectUrl })).toEqual({
      name: 'sso_login',
      query: { redirect_url: redirectUrl },
    });
  });
});

describe('Shopify signup and password recovery', () => {
  it('shows signup for a pending Shopify installation when public signup is disabled', () => {
    window.chatwootConfig = { signupEnabled: 'false' };

    expect(
      Login.computed.showSignupLink.call({
        signupRoute: {
          name: 'auth_signup',
          query: { shopify_pending_install: 'pending-token' },
        },
      })
    ).toBe(true);
  });

  it('carries the Shopify billing redirect to password recovery', () => {
    const planRedirect = 'settings/billing?plan_handle=growth';
    const route = Login.computed.resetPasswordRoute.call({
      redirectUrl: planRedirect,
      ssoAccountId: '42',
    });
    expect(route).toEqual({
      name: 'auth_reset_password',
      query: { redirect_url: planRedirect, sso_account_id: '42' },
    });
    const resetRoute = routes.find(item => item.name === 'auth_reset_password');
    const props = resetRoute.props(route);
    expect(props).toEqual({ redirectUrl: planRedirect, ssoAccountId: '42' });
    expect(
      getLoginRedirectURL({
        ...props,
        user: { account_id: 1, accounts: [{ id: 1 }, { id: 42 }] },
      })
    ).toBe('/app/accounts/42/settings/billing?plan_handle=growth');
  });

  it('carries a pending install redirect to email verification', async () => {
    const pendingInstallRedirect = `settings/integrations/shopify?shopify_pending_install=${'a'.repeat(32)}`;
    const router = { push: vi.fn() };
    const context = {
      email: '',
      credentials: {
        email: 'john@example.com',
        password: 'Password1!',
      },
      ssoAuthToken: '',
      ssoAccountId: '',
      ssoConversationId: '',
      redirectUrl: pendingInstallRedirect,
      loginApi: { showLoading: false, hasErrored: false },
      $router: router,
      handleImpersonation: vi.fn(),
      showAlertMessage: vi.fn(),
      $t: key => key,
    };
    login.mockRejectedValueOnce({ errorCode: 'user_not_confirmed' });

    Login.methods.submitLogin.call(context);
    await Promise.resolve();
    await Promise.resolve();

    expect(router.push).toHaveBeenCalledWith({
      name: 'auth_verify_email',
      state: {
        email: 'john@example.com',
        redirectUrl: pendingInstallRedirect,
      },
    });
  });
});

describe('login methods', () => {
  const mountLogin = (props = {}) =>
    mount(Login, {
      props,
      global: {
        plugins: [
          createStore({
            modules: {
              globalConfig: {
                namespaced: true,
                getters: { get: () => ({ logo: '/logo.svg' }) },
              },
            },
          }),
        ],
        mocks: { $t: key => key, $route: { query: {} } },
        stubs: {
          RouterLink: { template: '<a><slot /></a>' },
          FluentIcon: true,
        },
      },
    });

  afterEach(() => {
    window.chatwootConfig = {};
  });

  const findButton = (wrapper, testId) =>
    wrapper.find(`[data-testid="${testId}"]`);

  it('offers Pathors, then Google, then the password form', () => {
    window.chatwootConfig = {
      allowedLoginMethods: ['email', 'google_oauth', 'pathors'],
      googleOAuthClientId: 'google-client',
      googleOAuthCallbackUrl:
        'http://localhost:3000/omniauth/google_oauth2/callback',
      signupEnabled: 'true',
    };

    const wrapper = mountLogin({ redirectUrl: 'settings/billing' });
    const html = wrapper.html();

    expect(
      wrapper.find('form[data-testid="pathors-login"]').attributes('action')
    ).toBe('/omniauth/pathors?redirect_url=settings%2Fbilling');
    const googleHref = new URL(
      findButton(wrapper, 'google-login-button').attributes('href')
    );
    expect(googleHref.origin).toBe('https://accounts.google.com');
    expect(googleHref.searchParams.get('client_id')).toBe('google-client');
    expect(findButton(wrapper, 'email_input').exists()).toBe(true);
    expect(findButton(wrapper, 'password_input').exists()).toBe(true);
    expect(wrapper.find('.section-separator').text()).toBe('COMMON.OR');
    expect(wrapper.text()).toContain('LOGIN.FORGOT_PASSWORD');
    expect(wrapper.text()).toContain('LOGIN.CREATE_NEW_ACCOUNT');
    expect(html.indexOf('pathors-login-button')).toBeLessThan(
      html.indexOf('google-login-button')
    );
    expect(html.indexOf('google-login-button')).toBeLessThan(
      html.indexOf('section-separator')
    );
    expect(html.indexOf('section-separator')).toBeLessThan(
      html.indexOf('email_input')
    );
  });

  it('offers only the Pathors button when it is the only allowed method', () => {
    window.chatwootConfig = {
      allowedLoginMethods: ['pathors'],
      googleOAuthClientId: 'google-client',
    };

    const wrapper = mountLogin();

    expect(findButton(wrapper, 'pathors-login-button').exists()).toBe(true);
    expect(findButton(wrapper, 'google-login-button').exists()).toBe(false);
    expect(findButton(wrapper, 'email_input').exists()).toBe(false);
    expect(wrapper.find('.section-separator').exists()).toBe(false);
  });

  it('hides the Google button without a Google client id', () => {
    window.chatwootConfig = {
      allowedLoginMethods: ['email', 'google_oauth', 'pathors'],
    };

    const wrapper = mountLogin();

    expect(findButton(wrapper, 'pathors-login-button').exists()).toBe(true);
    expect(findButton(wrapper, 'google-login-button').exists()).toBe(false);
    expect(findButton(wrapper, 'email_input').exists()).toBe(true);
  });

  it('offers only the password form when no other method is allowed', () => {
    window.chatwootConfig = {
      allowedLoginMethods: ['email'],
      signupEnabled: 'true',
    };

    const wrapper = mountLogin();

    expect(findButton(wrapper, 'pathors-login-button').exists()).toBe(false);
    expect(findButton(wrapper, 'google-login-button').exists()).toBe(false);
    expect(wrapper.find('.section-separator').exists()).toBe(false);
    expect(findButton(wrapper, 'email_input').exists()).toBe(true);
    expect(findButton(wrapper, 'password_input').exists()).toBe(true);
    expect(wrapper.text()).toContain('LOGIN.FORGOT_PASSWORD');
    expect(wrapper.text()).toContain('LOGIN.CREATE_NEW_ACCOUNT');
  });

  it('auto-submits the SSO token returned from Pathors instead of showing the button', () => {
    window.chatwootConfig = { allowedLoginMethods: ['pathors'] };
    login.mockReturnValue(new Promise(() => {}));

    const wrapper = mountLogin({
      email: 'agent%40example.com',
      ssoAuthToken: 'sso-token',
      ssoAccountId: '42',
    });

    expect(wrapper.find('[data-testid="pathors-login-button"]').exists()).toBe(
      false
    );
    expect(login).toHaveBeenCalledWith(
      expect.objectContaining({
        email: 'agent@example.com',
        sso_auth_token: 'sso-token',
        ssoAccountId: '42',
      })
    );
  });

  it('explains a Pathors account mismatch from the error code', () => {
    expect(
      Login.methods.getTranslatedMessage.call(
        { $t: key => key },
        'LOGIN.PATHORS.ACCOUNT_MISMATCH'
      )
    ).toBe('LOGIN.PATHORS.ACCOUNT_MISMATCH');
  });
});
