import {
  consumeLoginReturnPath,
  rememberLoginReturnPath,
  sanitizeLoginReturnPath,
} from '../loginReturnPath';

const CONNECT_PATH =
  '/app/pathors/connect?organization_id=3f1c2d4e-5a6b-4c7d-8e9f-0a1b2c3d4e5f';

describe('loginReturnPath', () => {
  beforeEach(() => {
    window.sessionStorage.clear();
  });

  describe('#sanitizeLoginReturnPath', () => {
    it.each([
      CONNECT_PATH,
      '/app/accounts/1/dashboard',
      '/app/accounts/1/settings/integrations/pathors#inboxes',
    ])('keeps the in-app path %s', path => {
      expect(sanitizeLoginReturnPath(path)).toBe(path);
    });

    it.each([
      ['an absolute URL', 'https://evil.test/app/x'],
      // eslint-disable-next-line no-script-url
      ['a scheme', 'javascript:alert(1)'],
      ['a protocol-relative URL', '//evil.test/app/x'],
      ['a backslash authority', '/\\evil.test'],
      ['a backslash inside the path', '/app/\\evil.test'],
      ['a double slash inside the path', '/app//evil.test'],
      ['a path outside /app/', '/super_admin'],
      ['/app without the slash', '/app'],
      ['a lookalike prefix', '/application/x'],
      ['a relative path', 'app/accounts/1'],
      ['a parent segment', '/app/../super_admin'],
      ['a current segment', '/app/./accounts'],
      ['a trailing parent segment', '/app/accounts/..'],
      ['an encoded parent segment', '/app/%2e%2e/super_admin'],
      ['an encoded double slash', '/app/%2F%2Fevil.test'],
      ['an encoded backslash', '/app/%5Cevil.test'],
      ['a tab', '/app/\taccounts'],
      ['a newline', '/app/accounts\n/x'],
      ['a space', '/app/accounts 1'],
      ['malformed percent encoding', '/app/%E0%A4%A'],
      ['a non-string', ['/app/accounts/1']],
      ['an empty value', ''],
    ])('rejects %s', (_, path) => {
      expect(sanitizeLoginReturnPath(path)).toBeNull();
    });
  });

  it('remembers a valid path once', () => {
    rememberLoginReturnPath(CONNECT_PATH);

    expect(consumeLoginReturnPath()).toBe(CONNECT_PATH);
    expect(consumeLoginReturnPath()).toBeNull();
  });

  it('does not remember an unsafe path', () => {
    rememberLoginReturnPath('//evil.test');

    expect(window.sessionStorage.getItem('loginReturnPath')).toBeNull();
  });

  it('drops a stored value that is no longer a safe path', () => {
    window.sessionStorage.setItem('loginReturnPath', 'https://evil.test');

    expect(consumeLoginReturnPath()).toBeNull();
    expect(window.sessionStorage.getItem('loginReturnPath')).toBeNull();
  });
});
