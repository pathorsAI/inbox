<script setup>
import { computed } from 'vue';

const props = defineProps({
  redirectUrl: { type: String, default: '' },
  ssoAccountId: { type: String, default: '' },
  ssoConversationId: { type: String, default: '' },
  ssoRoutePath: { type: String, default: '' },
});

const PATHORS_LOGIN_PATH = '/omniauth/pathors';
// Served from public/ by Rails; bound at runtime so Vite does not try to bundle it.
const PATHORS_MARK_URL = '/brand-assets/logo_thumbnail.svg';

const csrfToken =
  document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') ||
  '';

// OmniAuth carries only the request phase's query string through the
// round trip, so the deep-link params go in the action URL, not the body.
const action = computed(() => {
  const query = new URLSearchParams(
    Object.entries({
      redirect_url: props.redirectUrl,
      sso_account_id: props.ssoAccountId,
      sso_conversation_id: props.ssoConversationId,
      sso_route_path: props.ssoRoutePath,
    }).filter(([, value]) => Boolean(value))
  ).toString();
  return query ? `${PATHORS_LOGIN_PATH}?${query}` : PATHORS_LOGIN_PATH;
});
</script>

<template>
  <form method="post" :action="action" data-testid="pathors-login">
    <input type="hidden" name="authenticity_token" :value="csrfToken" />
    <button
      type="submit"
      data-testid="pathors-login-button"
      class="flex items-center justify-center w-full h-11 gap-3 px-4 text-sm font-medium text-white transition-colors rounded-lg bg-n-brand hover:bg-n-brand/90 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand/50"
    >
      <img :src="PATHORS_MARK_URL" alt="" class="rounded size-5 bg-white" />
      <span>{{ $t('LOGIN.PATHORS.LOGIN') }}</span>
    </button>
  </form>
</template>
