import profileRoutes from '../profile.routes';

vi.mock('../../SettingsWrapper.vue', () => ({ default: {} }));
vi.mock('../Index.vue', () => ({ default: {} }));
vi.mock('../MfaSettings.vue', () => ({ default: {} }));

const mfaRoute = profileRoutes.routes[0].children.find(
  route => route.name === 'profile_settings_mfa'
);

describe('profile MFA route', () => {
  afterEach(() => {
    window.chatwootConfig = {};
  });

  it('opens when MFA is enabled and Pathors login is off', () => {
    window.chatwootConfig = {
      isMfaEnabled: 'true',
      pathorsLoginEnabled: 'false',
    };
    const next = vi.fn();

    mfaRoute.beforeEnter({}, {}, next);

    expect(next).toHaveBeenCalledWith();
  });

  it('redirects to profile settings under Pathors login', () => {
    window.chatwootConfig = {
      isMfaEnabled: 'true',
      pathorsLoginEnabled: 'true',
    };
    const next = vi.fn();

    mfaRoute.beforeEnter({}, {}, next);

    expect(next).toHaveBeenCalledWith({ name: 'profile_settings_index' });
  });
});
