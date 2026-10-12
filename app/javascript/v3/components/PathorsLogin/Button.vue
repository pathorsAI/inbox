<script setup>
import { computed } from 'vue';

const props = defineProps({
  // `google` still signs in through the Pathors OAuth client; the hint makes
  // Pathors open Google's account chooser instead of its own login form.
  provider: {
    type: String,
    default: 'pathors',
    validator: value => ['pathors', 'google'].includes(value),
  },
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

const isGoogle = computed(() => props.provider === 'google');

// OmniAuth carries only the request phase's query string through the
// round trip, so the deep-link params go in the action URL, not the body.
const action = computed(() => {
  const query = new URLSearchParams(
    Object.entries({
      idp_hint: isGoogle.value ? 'google' : '',
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
  <form
    method="post"
    :action="action"
    :data-testid="isGoogle ? 'google-login' : 'pathors-login'"
  >
    <input type="hidden" name="authenticity_token" :value="csrfToken" />
    <button
      v-if="isGoogle"
      type="submit"
      data-testid="google-login-button"
      class="flex items-center justify-center w-full h-11 gap-3 px-4 text-sm font-medium transition-colors border rounded-lg text-n-slate-12 border-n-weak bg-n-solid-1 hover:bg-n-alpha-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand/50"
    >
      <svg class="size-[18px]" viewBox="0 0 48 48" aria-hidden="true">
        <path
          fill="#FFC107"
          d="M43.6 20.5H42V20H24v8h11.3C33.7 32.7 29.2 36 24 36c-6.6 0-12-5.4-12-12s5.4-12 12-12c3.1 0 5.8 1.2 7.9 3.1l5.7-5.7C34 6.1 29.3 4 24 4 12.9 4 4 12.9 4 24s8.9 20 20 20 20-8.9 20-20c0-1.3-.1-2.4-.4-3.5z"
        />
        <path
          fill="#FF3D00"
          d="M6.3 14.7l6.6 4.8C14.7 15.1 19 12 24 12c3.1 0 5.8 1.2 7.9 3.1l5.7-5.7C34 6.1 29.3 4 24 4 16.3 4 9.7 8.3 6.3 14.7z"
        />
        <path
          fill="#4CAF50"
          d="M24 44c5.2 0 9.9-2 13.4-5.2l-6.2-5.2C29.2 35.1 26.7 36 24 36c-5.2 0-9.6-3.3-11.3-8l-6.5 5C9.5 39.6 16.2 44 24 44z"
        />
        <path
          fill="#1976D2"
          d="M43.6 20.5H42V20H24v8h11.3c-.8 2.2-2.2 4.2-4.1 5.6l6.2 5.2C37 39.2 44 34 44 24c0-1.3-.1-2.4-.4-3.5z"
        />
      </svg>
      <span>{{ $t('LOGIN.OAUTH.GOOGLE_LOGIN') }}</span>
    </button>
    <button
      v-else
      type="submit"
      data-testid="pathors-login-button"
      class="flex items-center justify-center w-full h-11 gap-3 px-4 text-sm font-medium text-white transition-colors rounded-lg bg-n-brand hover:bg-n-brand/90 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand/50"
    >
      <img :src="PATHORS_MARK_URL" alt="" class="rounded size-5 bg-white" />
      <span>{{ $t('LOGIN.PATHORS.LOGIN') }}</span>
    </button>
  </form>
</template>
