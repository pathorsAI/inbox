import SessionStorage from 'shared/helpers/sessionStorage';
import { SESSION_STORAGE_KEYS } from 'dashboard/constants/sessionStorage';

// Where to land after login. Chatwoot's login methods (password, MFA, Google,
// SAML, Platform SSO links) all end on the dashboard root, so the path waits in
// sessionStorage — same tab, survives the redirects — and the dashboard router
// takes it on its first navigation.
//
// It can come from outside (`/app/login?return_to=`), so only an in-app path
// is kept: it must start with /app/, stay on this origin, and read the same
// after one more round of decoding and after the browser normalises it.

const APP_PATH_PREFIX = '/app/';
// Printable ASCII only: no whitespace or control characters a browser could
// strip or reinterpret.
const NON_PRINTABLE_ASCII = /[^\x21-\x7e]/;
const DOT_SEGMENT = /(^|\/)\.{1,2}(\/|\?|#|$)/;

const isPlainAppPath = path =>
  path.startsWith(APP_PATH_PREFIX) &&
  !NON_PRINTABLE_ASCII.test(path) &&
  !path.includes('\\') &&
  !path.includes('//') &&
  !DOT_SEGMENT.test(path);

const decodeOnce = value => {
  try {
    return decodeURIComponent(value);
  } catch {
    return null;
  }
};

const isUnchangedOnThisOrigin = path => {
  const { origin } = window.location;
  const url = new URL(path, origin);
  return (
    url.origin === origin && `${url.pathname}${url.search}${url.hash}` === path
  );
};

export const sanitizeLoginReturnPath = value => {
  if (typeof value !== 'string' || !isPlainAppPath(value)) return null;

  const decoded = decodeOnce(value);
  if (decoded === null || !isPlainAppPath(decoded)) return null;

  return isUnchangedOnThisOrigin(value) ? value : null;
};

export const rememberLoginReturnPath = value => {
  const path = sanitizeLoginReturnPath(value);
  if (path) SessionStorage.set(SESSION_STORAGE_KEYS.LOGIN_RETURN_PATH, path);
};

// Read once: the entry is removed whether or not it is still valid.
export const consumeLoginReturnPath = () => {
  const path = SessionStorage.get(SESSION_STORAGE_KEYS.LOGIN_RETURN_PATH);
  if (path === null) return null;

  SessionStorage.remove(SESSION_STORAGE_KEYS.LOGIN_RETURN_PATH);
  return sanitizeLoginReturnPath(path);
};
