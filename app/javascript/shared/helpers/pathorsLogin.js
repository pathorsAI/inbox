import { parseBoolean } from '@chatwoot/utils';

export const isPathorsLoginEnabled = (config = window.chatwootConfig) =>
  parseBoolean(config?.pathorsLoginEnabled);
