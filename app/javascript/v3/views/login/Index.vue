<script>
// utils and composables
import { login } from '../../api/auth';
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { required, email } from '@vuelidate/validators';
import { useVuelidate } from '@vuelidate/core';
import { SESSION_STORAGE_KEYS } from 'dashboard/constants/sessionStorage';
import SessionStorage from 'shared/helpers/sessionStorage';
import { useBranding } from 'shared/composables/useBranding';
import AnalyticsHelper from 'dashboard/helper/AnalyticsHelper';
import { SESSION_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';
import { getLoginRedirectURL, getSignupRoute } from 'v3/helpers/AuthHelper';

// components
import SimpleDivider from '../../components/Divider/SimpleDivider.vue';
import FormInput from '../../components/Form/Input.vue';
import PathorsLoginButton from '../../components/PathorsLogin/Button.vue';
import Spinner from 'shared/components/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import MfaVerification from 'dashboard/components/auth/MfaVerification.vue';
import MfaEnforcedSetup from 'dashboard/components/auth/MfaEnforcedSetup.vue';
import SessionLimitOverlay from 'dashboard/components/auth/SessionLimitOverlay.vue';

const ERROR_MESSAGES = {
  'no-account-found': 'LOGIN.OAUTH.NO_ACCOUNT_FOUND',
  'business-account-only': 'LOGIN.OAUTH.BUSINESS_ACCOUNTS_ONLY',
  'shopify-installation-failed': 'LOGIN.OAUTH.SHOPIFY_INSTALLATION_FAILED',
  'saml-authentication-failed': 'LOGIN.SAML.API.ERROR_MESSAGE',
  'saml-not-enabled': 'LOGIN.SAML.API.ERROR_MESSAGE',
  'pathors-email-unverified': 'LOGIN.PATHORS.EMAIL_UNVERIFIED',
  'pathors-account-mismatch': 'LOGIN.PATHORS.ACCOUNT_MISMATCH',
  'pathors-login-failed': 'LOGIN.PATHORS.LOGIN_FAILED',
};

const IMPERSONATION_URL_SEARCH_KEY = 'impersonation';
const USER_NOT_CONFIRMED_ERROR_CODE = 'user_not_confirmed';
const AUTH_ERROR_TOAST_DURATION = 6000;

export default {
  components: {
    FormInput,
    PathorsLoginButton,
    Spinner,
    NextButton,
    SimpleDivider,
    MfaVerification,
    MfaEnforcedSetup,
    SessionLimitOverlay,
    Icon,
  },
  props: {
    ssoAuthToken: { type: String, default: '' },
    ssoAccountId: { type: String, default: '' },
    ssoConversationId: { type: String, default: '' },
    ssoRoutePath: { type: String, default: '' },
    email: { type: String, default: '' },
    authError: { type: String, default: '' },
    redirectUrl: { type: String, default: '' },
  },
  setup() {
    const { replaceInstallationName } = useBranding();
    return {
      replaceInstallationName,
      v$: useVuelidate(),
    };
  },
  data() {
    return {
      // We need to initialize the component with any
      // properties that will be used in it
      credentials: {
        email: '',
        password: '',
      },
      loginApi: {
        message: '',
        showLoading: false,
        hasErrored: false,
      },
      error: '',
      mfaRequired: false,
      mfaToken: null,
      mfaSetupRequired: false,
      mfaSetupToken: null,
      mfaProvisioningUrl: null,
      mfaSecret: null,
      verificationChannel: null,
      sessionsLimitReached: false,
      limitedSessions: [],
    };
  },
  validations() {
    return {
      credentials: {
        password: {
          required,
        },
        email: {
          required,
          email,
        },
      },
    };
  },
  computed: {
    ...mapGetters({ globalConfig: 'globalConfig/get' }),
    allowedLoginMethods() {
      return window.chatwootConfig.allowedLoginMethods || ['email'];
    },
    showPathorsLogin() {
      return this.allowedLoginMethods.includes('pathors');
    },
    // Google goes through the same Pathors client (one identity per email),
    // so it is offered exactly when Pathors login is.
    showGoogleLogin() {
      return this.showPathorsLogin;
    },
    showSignupLink() {
      if (this.showPathorsLogin) return false;
      return (
        window.chatwootConfig.signupEnabled === 'true' ||
        Boolean(this.signupRoute.query?.shopify_pending_install)
      );
    },
    signupRoute() {
      return getSignupRoute(this.redirectUrl);
    },
    resetPasswordRoute() {
      const route = { name: 'auth_reset_password' };
      return this.redirectUrl
        ? {
            ...route,
            query: {
              redirect_url: this.redirectUrl,
              ...(this.ssoAccountId
                ? { sso_account_id: this.ssoAccountId }
                : {}),
            },
          }
        : route;
    },
    showSamlLogin() {
      if (this.showPathorsLogin) return false;
      return this.allowedLoginMethods.includes('saml');
    },
    samlLoginRoute() {
      const route = { name: 'sso_login' };
      return this.redirectUrl || this.ssoAccountId
        ? {
            ...route,
            query: {
              redirect_url: this.redirectUrl,
              ...(this.ssoAccountId
                ? { sso_account_id: this.ssoAccountId }
                : {}),
            },
          }
        : route;
    },
  },
  created() {
    if (this.ssoAuthToken) {
      this.submitLogin();
    }
  },
  mounted() {
    if (this.authError) {
      // Wait for the sibling snackbar to mount and subscribe to toast events.
      this.$nextTick(() => {
        const messageKey = ERROR_MESSAGES[this.authError] ?? 'LOGIN.API.UNAUTH';
        // Use a method to get the translated text to avoid dynamic key warning
        const translatedMessage = this.getTranslatedMessage(messageKey);
        useAlert(translatedMessage, { duration: AUTH_ERROR_TOAST_DURATION });
        // wait for idle state
        this.requestIdleCallbackPolyfill(() => {
          // Remove the error query param from the url
          const { query } = this.$route;
          this.$router.replace({ query: { ...query, error: undefined } });
        });
      });
    }
  },
  methods: {
    getTranslatedMessage(key) {
      // Avoid dynamic key warning by handling each case explicitly
      switch (key) {
        case 'LOGIN.OAUTH.NO_ACCOUNT_FOUND':
          return this.$t('LOGIN.OAUTH.NO_ACCOUNT_FOUND');
        case 'LOGIN.OAUTH.BUSINESS_ACCOUNTS_ONLY':
          return this.$t('LOGIN.OAUTH.BUSINESS_ACCOUNTS_ONLY');
        case 'LOGIN.OAUTH.SHOPIFY_INSTALLATION_FAILED':
          return this.$t('LOGIN.OAUTH.SHOPIFY_INSTALLATION_FAILED');
        case 'LOGIN.PATHORS.EMAIL_UNVERIFIED':
          return this.$t('LOGIN.PATHORS.EMAIL_UNVERIFIED');
        case 'LOGIN.PATHORS.ACCOUNT_MISMATCH':
          return this.$t('LOGIN.PATHORS.ACCOUNT_MISMATCH');
        case 'LOGIN.PATHORS.LOGIN_FAILED':
          return this.$t('LOGIN.PATHORS.LOGIN_FAILED');
        case 'LOGIN.API.UNAUTH':
        default:
          return this.$t('LOGIN.API.UNAUTH');
      }
    },
    // TODO: Remove this when Safari gets wider support
    // Ref: https://caniuse.com/requestidlecallback
    //
    requestIdleCallbackPolyfill(callback) {
      if (window.requestIdleCallback) {
        window.requestIdleCallback(callback);
      } else {
        // Fallback for safari
        // Using a delay of 0 allows the callback to be executed asynchronously
        // in the next available event loop iteration, similar to requestIdleCallback
        setTimeout(callback, 0);
      }
    },
    showAlertMessage(message) {
      // Reset loading, current selected agent
      this.loginApi.showLoading = false;
      this.loginApi.message = message;
      useAlert(this.loginApi.message);
    },
    handleImpersonation() {
      // Detects impersonation mode via URL and sets a session flag to prevent user settings changes during impersonation.
      const urlParams = new URLSearchParams(window.location.search);
      const impersonation = urlParams.get(IMPERSONATION_URL_SEARCH_KEY);
      if (impersonation) {
        SessionStorage.set(SESSION_STORAGE_KEYS.IMPERSONATION_USER, true);
      }
    },
    submitLogin() {
      this.loginApi.hasErrored = false;
      this.loginApi.showLoading = true;

      const credentials = {
        email: this.email
          ? decodeURIComponent(this.email)
          : this.credentials.email,
        password: this.credentials.password,
        sso_auth_token: this.ssoAuthToken,
        ssoAccountId: this.ssoAccountId,
        ssoConversationId: this.ssoConversationId,
        ssoRoutePath: this.ssoRoutePath,
        redirectUrl: this.redirectUrl,
      };

      login(credentials)
        .then(result => {
          // Check if MFA is required
          if (result?.mfaRequired) {
            this.loginApi.showLoading = false;
            this.mfaRequired = true;
            this.mfaToken = result.mfaToken;
            this.verificationChannel = result.verificationChannel || null;
            return;
          }

          // Check if the account enforces MFA and setup is pending
          if (result?.mfaSetupRequired) {
            this.loginApi.showLoading = false;
            this.mfaSetupRequired = true;
            this.mfaSetupToken = result.mfaSetupToken;
            this.mfaProvisioningUrl = result.provisioningUrl;
            this.mfaSecret = result.secret;
            return;
          }

          // Check if sessions limit reached
          if (result?.sessionsLimitReached) {
            this.loginApi.showLoading = false;
            this.sessionsLimitReached = true;
            this.limitedSessions = result.sessions;
            AnalyticsHelper.track(SESSION_EVENTS.LIMIT_HIT);
            return;
          }

          this.handleImpersonation();
          this.showAlertMessage(this.$t('LOGIN.API.SUCCESS_MESSAGE'));
        })
        .catch(response => {
          if (response?.errorCode === USER_NOT_CONFIRMED_ERROR_CODE) {
            this.loginApi.showLoading = false;
            this.$router.push({
              name: 'auth_verify_email',
              state: {
                email: credentials.email,
                redirectUrl: this.redirectUrl,
              },
            });
            return;
          }

          // Reset URL Params if the authentication is invalid
          if (this.email) {
            window.location = '/app/login';
          }
          this.loginApi.hasErrored = true;
          this.showAlertMessage(
            response?.message || this.$t('LOGIN.API.UNAUTH')
          );
        });
    },
    submitFormLogin() {
      if (this.v$.credentials.email.$invalid && !this.email) {
        this.showAlertMessage(this.$t('LOGIN.EMAIL.ERROR'));
        return;
      }

      this.submitLogin();
    },
    handleMfaVerified(user) {
      // Continue with the requested Shopify, account, or conversation destination.
      this.handleImpersonation();
      window.location = getLoginRedirectURL({
        ssoAccountId: this.ssoAccountId,
        ssoConversationId: this.ssoConversationId,
        redirectUrl: this.redirectUrl,
        user,
      });
    },
    handleMfaCancel() {
      // User cancelled MFA, reset state
      this.mfaRequired = false;
      this.mfaToken = null;
      this.verificationChannel = null;
      this.credentials.password = '';
    },
    // Device verification passed but the account still requires enrolment;
    // swap the challenge screen for the setup wizard.
    handleMfaSetupRequired(data) {
      this.mfaRequired = false;
      this.mfaToken = null;
      this.verificationChannel = null;
      this.mfaSetupRequired = true;
      this.mfaSetupToken = data.mfa_setup_token;
      this.mfaProvisioningUrl = data.provisioning_url;
      this.mfaSecret = data.secret;
    },
    handleMfaSetupVerified(data) {
      this.handleImpersonation();
      window.location = getLoginRedirectURL({
        ssoAccountId: this.ssoAccountId,
        ssoConversationId: this.ssoConversationId,
        redirectUrl: this.redirectUrl,
        user: data?.data,
      });
    },
    handleMfaSetupCancel() {
      this.mfaSetupRequired = false;
      this.mfaSetupToken = null;
      this.mfaProvisioningUrl = null;
      this.mfaSecret = null;
      this.credentials.password = '';
    },
    retryLoginWithParams(extraParams) {
      const credentials = {
        email: this.email
          ? decodeURIComponent(this.email)
          : this.credentials.email,
        password: this.credentials.password,
        sso_auth_token: this.ssoAuthToken,
        ssoAccountId: this.ssoAccountId,
        ssoConversationId: this.ssoConversationId,
        ssoRoutePath: this.ssoRoutePath,
        redirectUrl: this.redirectUrl,
        ...extraParams,
      };

      this.sessionsLimitReached = false;
      this.limitedSessions = [];
      this.loginApi.showLoading = true;
      login(credentials)
        .then(result => {
          if (result?.mfaRequired) {
            this.loginApi.showLoading = false;
            this.mfaRequired = true;
            this.mfaToken = result.mfaToken;
            this.verificationChannel = result.verificationChannel || null;
            return;
          }
          if (result?.sessionsLimitReached) {
            this.loginApi.showLoading = false;
            this.sessionsLimitReached = true;
            this.limitedSessions = result.sessions;
            AnalyticsHelper.track(SESSION_EVENTS.LIMIT_HIT);
            return;
          }
          this.handleImpersonation();
          this.showAlertMessage(this.$t('LOGIN.API.SUCCESS_MESSAGE'));
        })
        .catch(response => {
          this.loginApi.hasErrored = true;
          this.showAlertMessage(
            response?.message || this.$t('LOGIN.API.UNAUTH')
          );
        });
    },
    handleSessionRevoke(sessionId) {
      this.retryLoginWithParams({ revoke_session_id: sessionId });
    },
    handleSessionRevokeAll() {
      this.retryLoginWithParams({ revoke_all_sessions: true });
    },
    handleSessionLimitCancel() {
      this.sessionsLimitReached = false;
      this.limitedSessions = [];
      this.credentials.password = '';
    },
  },
};
</script>

<template>
  <!-- The sign-in screen is always dark: `dark` switches the n-* tokens so the
       password, SAML and MFA fallbacks render on the same canvas. -->
  <main
    class="dark relative flex items-center justify-center w-full min-h-screen px-4 py-16 overflow-hidden bg-[#05070B] isolate"
  >
    <div class="absolute inset-0 login-grid -z-10" aria-hidden="true" />
    <div
      class="absolute -top-56 left-1/2 -z-10 h-[560px] w-[880px] -translate-x-1/2 rounded-full bg-[#2781F6]/25 blur-[120px]"
      aria-hidden="true"
    />
    <div
      class="absolute -bottom-64 -right-40 -z-10 size-[480px] rounded-full bg-[#22D3EE]/10 blur-[120px]"
      aria-hidden="true"
    />
    <div
      class="absolute inset-x-0 top-0 h-40 login-scan -z-10"
      aria-hidden="true"
    />

    <div class="relative w-full max-w-[420px]">
      <header class="flex flex-col items-center text-center">
        <img
          :src="globalConfig.logoDark || globalConfig.logo"
          :alt="globalConfig.installationName"
          class="block w-auto h-7"
        />
        <p
          class="inline-flex items-center gap-2 px-3 py-1 mt-9 font-mono text-[11px] uppercase tracking-[0.24em] text-[#8DBBFF] border rounded-full border-[#2781F6]/25 bg-[#2781F6]/[0.08]"
        >
          <span class="relative flex size-1.5" aria-hidden="true">
            <span
              class="absolute inline-flex w-full h-full rounded-full opacity-75 bg-[#4DA3FF] login-ping"
            />
            <span
              class="relative inline-flex rounded-full size-1.5 bg-[#4DA3FF]"
            />
          </span>
          {{ $t('LOGIN.EYEBROW') }}
        </p>
        <h1 class="mt-4 text-[28px] font-semibold tracking-tight text-white">
          {{ replaceInstallationName($t('LOGIN.TITLE')) }}
        </h1>
        <p v-if="showPathorsLogin" class="mt-2 text-sm text-white/55">
          {{ $t('LOGIN.PATHORS.SUBTITLE') }}
        </p>
        <p v-if="showSignupLink" class="mt-2 text-sm text-white/55">
          {{ $t('COMMON.OR') }}
          <router-link
            :to="signupRoute"
            class="lowercase text-link text-[#8DBBFF]"
          >
            {{ $t('LOGIN.CREATE_NEW_ACCOUNT') }}
          </router-link>
        </p>
      </header>

      <!-- Session Limit Section -->
      <section v-if="sessionsLimitReached" class="mt-10">
        <SessionLimitOverlay
          :sessions="limitedSessions"
          @revoke="handleSessionRevoke"
          @revoke-all="handleSessionRevokeAll"
          @cancel="handleSessionLimitCancel"
        />
      </section>

      <!-- MFA Verification Section -->
      <section v-else-if="mfaRequired" class="mt-10">
        <MfaVerification
          :mfa-token="mfaToken"
          :verification-channel="verificationChannel"
          @verified="handleMfaVerified"
          @setup-required="handleMfaSetupRequired"
          @cancel="handleMfaCancel"
        />
      </section>

      <!-- Enforced MFA Setup Section -->
      <section v-else-if="mfaSetupRequired" class="mt-10">
        <MfaEnforcedSetup
          :mfa-setup-token="mfaSetupToken"
          :provisioning-url="mfaProvisioningUrl"
          :secret="mfaSecret"
          @verified="handleMfaSetupVerified"
          @cancel="handleMfaSetupCancel"
        />
      </section>

      <!-- Regular Login Section -->
      <section
        v-else
        class="relative mt-10 login-card rounded-2xl border border-white/10 bg-[#0B0F17]/70 p-8 shadow-[0_24px_80px_-24px_rgba(0,0,0,0.9)] backdrop-blur-xl"
        :class="{ 'animate-wiggle': loginApi.hasErrored }"
      >
        <span
          class="absolute inset-x-10 -top-px h-px bg-gradient-to-r from-transparent via-[#4DA3FF] to-transparent"
          aria-hidden="true"
        />
        <div v-if="!email">
          <div class="flex flex-col gap-3">
            <PathorsLoginButton
              v-if="showPathorsLogin"
              :redirect-url="redirectUrl"
              :sso-account-id="ssoAccountId"
              :sso-conversation-id="ssoConversationId"
              :sso-route-path="ssoRoutePath"
            />
            <div
              v-if="showGoogleLogin"
              class="flex items-center gap-3 my-1 font-mono text-[11px] uppercase tracking-[0.2em] text-white/30"
            >
              <span class="flex-1 h-px bg-white/10" />
              {{ $t('COMMON.OR') }}
              <span class="flex-1 h-px bg-white/10" />
            </div>
            <PathorsLoginButton
              v-if="showGoogleLogin"
              provider="google"
              :redirect-url="redirectUrl"
              :sso-account-id="ssoAccountId"
              :sso-conversation-id="ssoConversationId"
              :sso-route-path="ssoRoutePath"
            />
            <div v-if="showSamlLogin" class="text-center">
              <router-link
                :to="samlLoginRoute"
                class="inline-flex items-center justify-center w-full h-12 px-4 border rounded-xl border-white/10 bg-white/[0.03] hover:bg-white/[0.07]"
              >
                <Icon
                  icon="i-lucide-lock-keyhole"
                  class="size-5 text-n-slate-11"
                />
                <span class="ml-2 text-sm font-medium text-n-slate-12">
                  {{ $t('LOGIN.SAML.LABEL') }}
                </span>
              </router-link>
            </div>
            <SimpleDivider
              v-if="showSamlLogin"
              :label="$t('COMMON.OR')"
              bg="bg-[#0B0F17]"
              class="uppercase"
            />
          </div>
          <form
            v-if="!showPathorsLogin"
            class="space-y-5"
            @submit.prevent="submitFormLogin"
          >
            <FormInput
              v-model="credentials.email"
              name="email_address"
              type="text"
              data-testid="email_input"
              :tabindex="1"
              required
              :label="$t('LOGIN.EMAIL.LABEL')"
              :placeholder="$t('LOGIN.EMAIL.PLACEHOLDER')"
              :has-error="v$.credentials.email.$error"
              @input="v$.credentials.email.$touch"
            />
            <FormInput
              v-model="credentials.password"
              type="password"
              name="password"
              data-testid="password_input"
              required
              :tabindex="2"
              :label="$t('LOGIN.PASSWORD.LABEL')"
              :placeholder="$t('LOGIN.PASSWORD.PLACEHOLDER')"
              :has-error="v$.credentials.password.$error"
              @input="v$.credentials.password.$touch"
            >
              <p v-if="!globalConfig.disableUserProfileUpdate">
                <router-link
                  :to="resetPasswordRoute"
                  class="text-sm text-link"
                  tabindex="4"
                >
                  {{ $t('LOGIN.FORGOT_PASSWORD') }}
                </router-link>
              </p>
            </FormInput>
            <NextButton
              lg
              type="submit"
              data-testid="submit_button"
              class="w-full"
              :tabindex="3"
              :label="$t('LOGIN.SUBMIT')"
              :disabled="loginApi.showLoading"
              :is-loading="loginApi.showLoading"
            />
          </form>
        </div>
        <div v-else class="flex items-center justify-center py-6">
          <Spinner color-scheme="primary" size="" />
        </div>
      </section>

      <p
        v-if="showPathorsLogin"
        class="mt-6 text-xs leading-relaxed text-center text-white/35 text-balance"
      >
        {{ $t('LOGIN.PATHORS.SAME_ACCOUNT_HINT') }}
      </p>
    </div>
  </main>
</template>

<style scoped>
.login-grid {
  background-image: linear-gradient(
      rgba(77, 163, 255, 0.07) 1px,
      transparent 1px
    ),
    linear-gradient(90deg, rgba(77, 163, 255, 0.07) 1px, transparent 1px);
  background-size: 48px 48px;
  mask-image: radial-gradient(
    ellipse 70% 60% at 50% 35%,
    #000 30%,
    transparent 75%
  );
  animation: login-grid-drift 24s linear infinite;
}

.login-scan {
  background: linear-gradient(
    180deg,
    transparent,
    rgba(77, 163, 255, 0.025) 80%,
    rgba(77, 163, 255, 0.22) 100%
  );
  animation: login-scan 9s cubic-bezier(0.45, 0, 0.55, 1) infinite;
}

/* Corner ticks on the card. */
.login-card::before,
.login-card::after {
  content: '';
  position: absolute;
  width: 14px;
  height: 14px;
  border-color: rgba(77, 163, 255, 0.55);
  pointer-events: none;
}

.login-card::before {
  top: -1px;
  left: -1px;
  border-top: 1px solid;
  border-left: 1px solid;
  border-top-left-radius: 1rem;
}

.login-card::after {
  right: -1px;
  bottom: -1px;
  border-right: 1px solid;
  border-bottom: 1px solid;
  border-bottom-right-radius: 1rem;
}

.login-ping {
  animation: login-ping 2s cubic-bezier(0, 0, 0.2, 1) infinite;
}

@keyframes login-grid-drift {
  to {
    background-position: 48px 48px;
  }
}

@keyframes login-scan {
  0% {
    transform: translateY(-160px);
  }
  100% {
    transform: translateY(100vh);
  }
}

@keyframes login-ping {
  75%,
  100% {
    transform: scale(2.4);
    opacity: 0;
  }
}

@media (prefers-reduced-motion: reduce) {
  .login-grid,
  .login-scan,
  .login-ping {
    animation: none;
  }

  .login-scan {
    display: none;
  }
}
</style>
