import { parseBoolean } from '@chatwoot/utils';

export const isPathorsLoginEnabled = (config = window.chatwootConfig) =>
  parseBoolean(config?.pathorsLoginEnabled);

// Pathors owns the second factor when it owns the login, so the per-user MFA
// screens are hidden; the account-level "enforce MFA" setting is unaffected.
export const isProfileMfaAvailable = (config = window.chatwootConfig) =>
  parseBoolean(config?.isMfaEnabled) && !isPathorsLoginEnabled(config);
