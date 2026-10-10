import { mount } from '@vue/test-utils';
import PathorsLoginButton from './Button.vue';

const mountButton = props =>
  mount(PathorsLoginButton, {
    props,
    global: { mocks: { $t: key => key } },
  });

const hiddenFields = wrapper =>
  Object.fromEntries(
    wrapper
      .findAll('input[type="hidden"]')
      .map(input => [input.attributes('name'), input.element.value])
  );

describe('PathorsLoginButton', () => {
  beforeEach(() => {
    document.head.innerHTML = '<meta name="csrf-token" content="csrf-123">';
  });

  afterEach(() => {
    document.head.innerHTML = '';
  });

  it('posts to the Pathors OmniAuth path with only the CSRF token when there is no deep link', () => {
    const wrapper = mountButton();
    const form = wrapper.find('form[data-testid="pathors-login"]');

    expect(form.attributes('method')).toBe('post');
    expect(form.attributes('action')).toBe('/omniauth/pathors');
    expect(hiddenFields(wrapper)).toEqual({ authenticity_token: 'csrf-123' });
    expect(
      wrapper.find('[data-testid="pathors-login-button"]').attributes('type')
    ).toBe('submit');
  });

  it('carries only the non-empty deep-link params in the action query', () => {
    const wrapper = mountButton({
      redirectUrl: 'settings/billing?plan_handle=growth',
      ssoAccountId: '42',
      ssoConversationId: '',
      ssoRoutePath: 'conversations/7',
    });

    expect(
      wrapper.find('form[data-testid="pathors-login"]').attributes('action')
    ).toBe(
      '/omniauth/pathors?redirect_url=settings%2Fbilling%3Fplan_handle%3Dgrowth&sso_account_id=42&sso_route_path=conversations%2F7'
    );
    expect(hiddenFields(wrapper)).toEqual({ authenticity_token: 'csrf-123' });
  });
});
