import { parseBoolean } from '@chatwoot/utils';

export const isPathorsLoginEnabled = (config = globalThis.chatwootConfig) =>
  parseBoolean(config?.pathorsLoginEnabled);
