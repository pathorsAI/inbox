<script setup>
import { computed } from 'vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  redirectUrl: { type: String, default: '' },
  ssoAccountId: { type: String, default: '' },
  ssoConversationId: { type: String, default: '' },
  ssoRoutePath: { type: String, default: '' },
});

const PATHORS_LOGIN_PATH = '/omniauth/pathors';

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
    <NextButton
      lg
      type="submit"
      class="w-full"
      data-testid="pathors-login-button"
      :label="$t('LOGIN.PATHORS.LOGIN')"
    />
  </form>
</template>
