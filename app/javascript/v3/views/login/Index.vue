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

// Served from public/ by Rails; bound at runtime so Vite does not bundle them.
const LOGO_MARK_URL = '/favicon-512x512.png';
const LOGIN_ART_SLIDES = [
  '/brand-assets/login-art-1.jpg',
  '/brand-assets/login-art-2.jpg',
  '/brand-assets/login-art-3.jpg',
];
// Each slide is on screen this long; the cycle is slides × this.
const LOGIN_ART_SLIDE_SECONDS = 8;

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
      LOGO_MARK_URL,
      LOGIN_ART_SLIDES,
      LOGIN_ART_SLIDE_SECONDS,
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
  <main class="flex w-full min-h-screen bg-n-background">
    <section
      class="flex items-center justify-center flex-1 px-6 py-12 sm:px-10"
    >
      <div class="w-full max-w-sm">
        <div class="flex items-center gap-3">
          <img
            :src="LOGO_MARK_URL"
            :alt="globalConfig.installationName"
            class="size-10 shrink-0"
          />
          <h1 class="text-2xl font-semibold tracking-tight text-n-slate-12">
            {{ replaceInstallationName($t('LOGIN.TITLE')) }}
          </h1>
        </div>
        <p v-if="showSignupLink" class="mt-2 text-sm text-n-slate-11">
          {{ $t('COMMON.OR') }}
          <router-link
            :to="signupRoute"
            class="lowercase text-link text-n-brand"
          >
            {{ $t('LOGIN.CREATE_NEW_ACCOUNT') }}
          </router-link>
        </p>

        <!-- Session Limit Section -->
        <div v-if="sessionsLimitReached" class="mt-8">
          <SessionLimitOverlay
            :sessions="limitedSessions"
            @revoke="handleSessionRevoke"
            @revoke-all="handleSessionRevokeAll"
            @cancel="handleSessionLimitCancel"
          />
        </div>

        <!-- MFA Verification Section -->
        <div v-else-if="mfaRequired" class="mt-8">
          <MfaVerification
            :mfa-token="mfaToken"
            :verification-channel="verificationChannel"
            @verified="handleMfaVerified"
            @setup-required="handleMfaSetupRequired"
            @cancel="handleMfaCancel"
          />
        </div>

        <!-- Enforced MFA Setup Section -->
        <div v-else-if="mfaSetupRequired" class="mt-8">
          <MfaEnforcedSetup
            :mfa-setup-token="mfaSetupToken"
            :provisioning-url="mfaProvisioningUrl"
            :secret="mfaSecret"
            @verified="handleMfaSetupVerified"
            @cancel="handleMfaSetupCancel"
          />
        </div>

        <!-- Regular Login Section -->
        <div
          v-else
          class="mt-8"
          :class="{ 'animate-wiggle': loginApi.hasErrored }"
        >
          <div v-if="!email">
            <div class="flex flex-col gap-3">
              <PathorsLoginButton
                v-if="showPathorsLogin"
                :redirect-url="redirectUrl"
                :sso-account-id="ssoAccountId"
                :sso-conversation-id="ssoConversationId"
                :sso-route-path="ssoRoutePath"
              />
              <SimpleDivider
                v-if="showGoogleLogin"
                :label="$t('COMMON.OR')"
                bg="bg-n-background"
              />
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
                  class="inline-flex items-center justify-center w-full h-11 px-4 border rounded-lg border-n-weak bg-n-solid-1 hover:bg-n-alpha-2"
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
                bg="bg-n-background"
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
        </div>
      </div>
    </section>

    <!-- Artwork only, no copy; hidden below lg where the form takes the screen. -->
    <aside
      class="sticky top-0 hidden h-screen p-3 lg:block lg:w-1/2 xl:w-[55%]"
    >
      <div class="relative h-full overflow-hidden rounded-2xl bg-black">
        <!-- The first slide also sits still underneath: it is what shows
             before the cycle fades in, and all that shows under reduced motion. -->
        <img
          :src="LOGIN_ART_SLIDES[0]"
          alt=""
          class="absolute inset-0 object-cover size-full"
        />
        <img
          v-for="(slide, index) in LOGIN_ART_SLIDES"
          :key="slide"
          :src="slide"
          alt=""
          class="absolute inset-0 object-cover opacity-0 size-full animate-login-slide motion-reduce:hidden"
          :style="{
            animationDelay: `${index * LOGIN_ART_SLIDE_SECONDS}s`,
            animationDuration: `${LOGIN_ART_SLIDES.length * LOGIN_ART_SLIDE_SECONDS}s`,
          }"
        />
        <div
          class="absolute inset-0 bg-[radial-gradient(rgb(255_255_255/0.16)_1px,transparent_1px)] bg-[length:1.5rem_1.5rem] [mask-image:linear-gradient(to_bottom,transparent,black_30%,black_70%,transparent)]"
          aria-hidden="true"
        />
        <div
          class="absolute inset-0 bg-[radial-gradient(ellipse_at_center,transparent_45%,rgb(0_0_0/0.5))]"
          aria-hidden="true"
        />
      </div>
    </aside>
  </main>
</template>
