<script setup>
import { computed, watch } from 'vue';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { usePathorsCallNotifyPreference } from 'dashboard/composables/usePathorsCallNotifyPreference';

// Asks once, while the agent is online, whether calls that need a human
// should reach the desktop. Answered for good by turning it on (here, in the
// avatar menu or the notification preferences) or by 不用; the avatar menu
// switch stays either way.
const DISMISSED_KEY = 'pathors_call_notify_prompt_dismissed';

const { uiSettings, updateUISettings } = useUISettings();
const preference = usePathorsCallNotifyPreference();

watch(
  preference.isAvailable,
  available => {
    if (available) preference.ensureLoaded();
  },
  { immediate: true }
);

const shouldShow = computed(
  () =>
    preference.isAvailable.value &&
    preference.isSupported &&
    preference.isLoaded.value &&
    !preference.isOn.value &&
    preference.isOnDuty.value &&
    !uiSettings.value?.[DISMISSED_KEY]
);

const enable = () => preference.setOn(true);
const decline = () => updateUISettings({ [DISMISSED_KEY]: true });
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <div
    v-if="shouldShow"
    class="flex items-center justify-between gap-3 px-4 py-2 text-sm border-b bg-n-blue-3 border-n-blue-4 text-n-blue-11"
    data-test-id="pathors-call-notify-banner"
  >
    <div class="flex items-center min-w-0 gap-2">
      <span class="shrink-0 i-lucide-bell-ring size-4" />
      <span class="truncate">{{ $t('CALLS_PAGE.NOTIFY.PROMPT') }}</span>
    </div>
    <div class="flex items-center gap-1 shrink-0">
      <button
        type="button"
        class="px-3 py-1 rounded-lg whitespace-nowrap bg-n-blue-4 hover:bg-n-blue-5"
        data-test-id="pathors-call-notify-enable"
        @click="enable"
      >
        {{ $t('CALLS_PAGE.NOTIFY.PROMPT_ENABLE') }}
      </button>
      <button
        type="button"
        class="px-3 py-1 rounded-lg whitespace-nowrap hover:bg-n-blue-4"
        data-test-id="pathors-call-notify-decline"
        @click="decline"
      >
        {{ $t('CALLS_PAGE.NOTIFY.PROMPT_DECLINE') }}
      </button>
    </div>
  </div>
</template>
