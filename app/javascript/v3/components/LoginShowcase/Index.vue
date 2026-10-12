<script setup>
import { computed, ref, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';

// A looping product demo beside the sign-in form: four short scenes, each a
// feature of the Inbox. Decorative, so it is hidden from assistive tech.
const SCENES = ['CHANNELS', 'VOICE', 'REPLY', 'HANDOFF'];
const SCENE_MS = 4500;

// Heights of the call waveform bars, as fractions of the strip.
const WAVE_BARS = [
  0.35, 0.6, 0.9, 0.5, 0.75, 1, 0.55, 0.8, 0.4, 0.7, 0.95, 0.5, 0.65, 0.85,
  0.45, 0.7, 0.3, 0.6, 0.9, 0.5,
];

const { t } = useI18n();

// Literal keys throughout, so the i18n lint and key extraction see them all.
const captions = computed(() => ({
  CHANNELS: t('LOGIN.SHOWCASE.CHANNELS.CAPTION'),
  VOICE: t('LOGIN.SHOWCASE.VOICE.CAPTION'),
  REPLY: t('LOGIN.SHOWCASE.REPLY.CAPTION'),
  HANDOFF: t('LOGIN.SHOWCASE.HANDOFF.CAPTION'),
}));

const channelRows = computed(() => [
  {
    key: 'phone',
    icon: 'i-lucide-phone',
    tint: 'bg-n-teal-9',
    name: t('LOGIN.SHOWCASE.CHANNELS.ROW_1.NAME'),
    text: t('LOGIN.SHOWCASE.CHANNELS.ROW_1.TEXT'),
  },
  {
    key: 'line',
    icon: 'i-ri-line-fill',
    // LINE's own brand green; the n-* palette has no green.
    tint: 'bg-[#06C755]',
    name: t('LOGIN.SHOWCASE.CHANNELS.ROW_2.NAME'),
    text: t('LOGIN.SHOWCASE.CHANNELS.ROW_2.TEXT'),
  },
  {
    key: 'email',
    icon: 'i-lucide-mail',
    tint: 'bg-n-amber-9',
    name: t('LOGIN.SHOWCASE.CHANNELS.ROW_3.NAME'),
    text: t('LOGIN.SHOWCASE.CHANNELS.ROW_3.TEXT'),
  },
  {
    key: 'web',
    icon: 'i-lucide-globe',
    tint: 'bg-n-iris-9',
    name: t('LOGIN.SHOWCASE.CHANNELS.ROW_4.NAME'),
    text: t('LOGIN.SHOWCASE.CHANNELS.ROW_4.TEXT'),
  },
]);

const current = ref(0);
let timer = null;

const prefersReducedMotion = () =>
  globalThis.matchMedia?.('(prefers-reduced-motion: reduce)').matches ?? false;

const stagger = index => ({ animationDelay: `${0.25 + index * 0.35}s` });

onMounted(() => {
  if (prefersReducedMotion()) return;
  timer = setInterval(() => {
    current.value = (current.value + 1) % SCENES.length;
  }, SCENE_MS);
});

onBeforeUnmount(() => clearInterval(timer));
</script>

<template>
  <div
    class="flex flex-col w-full max-w-md gap-5 text-white"
    aria-hidden="true"
    data-testid="login-showcase"
  >
    <Transition
      mode="out-in"
      enter-active-class="transition duration-500 ease-out"
      enter-from-class="translate-y-2 opacity-0"
      leave-active-class="transition duration-300 ease-in"
      leave-to-class="-translate-y-2 opacity-0"
    >
      <p
        :key="`caption-${current}`"
        class="text-xl font-semibold tracking-tight text-white text-balance"
      >
        {{ captions[SCENES[current]] }}
      </p>
    </Transition>

    <div
      class="relative flex flex-col min-h-[19rem] overflow-hidden rounded-2xl bg-white/10 p-5 ring-1 ring-inset ring-white/15 backdrop-blur-xl shadow-[0_24px_64px_-24px_rgb(0_0_0/0.6)]"
    >
      <Transition
        mode="out-in"
        enter-active-class="transition duration-500 ease-out"
        enter-from-class="scale-[0.98] opacity-0"
        leave-active-class="transition duration-300 ease-in"
        leave-to-class="scale-[0.98] opacity-0"
      >
        <!-- Channels: conversations from every channel land in one list. -->
        <div
          v-if="SCENES[current] === 'CHANNELS'"
          key="CHANNELS"
          class="flex flex-col gap-2"
          data-testid="showcase-scene-CHANNELS"
        >
          <p class="mb-1 text-xs font-medium text-white/60">
            {{ $t('LOGIN.SHOWCASE.CHANNELS.TITLE') }}
          </p>
          <div
            v-for="(row, index) in channelRows"
            :key="row.key"
            class="flex items-center gap-3 p-2.5 rounded-xl bg-white/[0.08] motion-safe:animate-showcase-rise"
            :style="stagger(index)"
          >
            <span
              class="flex items-center justify-center rounded-lg size-8 shrink-0"
              :class="row.tint"
            >
              <span class="size-4" :class="row.icon" />
            </span>
            <div class="flex-1 min-w-0">
              <p class="text-sm font-medium truncate">
                {{ row.name }}
              </p>
              <p class="text-xs truncate text-white/60">
                {{ row.text }}
              </p>
            </div>
            <span class="text-[0.6875rem] text-white/50 shrink-0">
              {{ $t('LOGIN.SHOWCASE.CHANNELS.NOW') }}
            </span>
          </div>
        </div>

        <!-- Voice: AI answers the call and transcribes it live. -->
        <div
          v-else-if="SCENES[current] === 'VOICE'"
          key="VOICE"
          class="flex flex-col gap-4"
          data-testid="showcase-scene-VOICE"
        >
          <div class="flex items-center gap-3">
            <span
              class="flex items-center justify-center rounded-full size-10 bg-n-teal-9"
            >
              <span class="i-lucide-phone size-5" />
            </span>
            <div class="flex-1">
              <p class="text-sm font-medium">
                {{ $t('LOGIN.SHOWCASE.CHANNELS.ROW_1.NAME') }}
              </p>
              <p class="flex items-center gap-1.5 text-xs text-white/60">
                <span
                  class="rounded-full size-1.5 bg-n-teal-9 motion-safe:animate-pulse"
                />
                {{ $t('LOGIN.SHOWCASE.VOICE.STATUS') }}
              </p>
            </div>
          </div>
          <div class="flex items-center justify-between h-10 px-1">
            <span
              v-for="(height, index) in WAVE_BARS"
              :key="index"
              class="w-1 rounded-full origin-center bg-white/70 motion-safe:animate-showcase-wave"
              :style="{
                height: `${height * 100}%`,
                animationDelay: `${(index % 5) * 0.12}s`,
              }"
            />
          </div>
          <div class="flex flex-col gap-2">
            <p
              class="self-start max-w-[85%] px-3 py-2 text-sm rounded-2xl rounded-bl-md bg-white/[0.12] motion-safe:animate-showcase-rise"
              :style="stagger(1)"
            >
              {{ $t('LOGIN.SHOWCASE.VOICE.CUSTOMER') }}
            </p>
            <p
              class="self-end max-w-[85%] px-3 py-2 text-sm rounded-2xl rounded-br-md bg-n-brand motion-safe:animate-showcase-rise"
              :style="stagger(3)"
            >
              {{ $t('LOGIN.SHOWCASE.VOICE.AI') }}
            </p>
          </div>
        </div>

        <!-- Reply: AI answers a message from the knowledge base. -->
        <div
          v-else-if="SCENES[current] === 'REPLY'"
          key="REPLY"
          class="flex flex-col gap-3 mt-auto"
          data-testid="showcase-scene-REPLY"
        >
          <p
            class="self-start max-w-[85%] px-3 py-2 text-sm rounded-2xl rounded-bl-md bg-white/[0.12] motion-safe:animate-showcase-rise"
            :style="stagger(0)"
          >
            {{ $t('LOGIN.SHOWCASE.REPLY.QUESTION') }}
          </p>
          <!-- The typing dots and the answer share one cell, so the answer
               takes the dots' place instead of appearing below a gap. -->
          <div class="grid self-end max-w-[85%] justify-items-end">
            <div
              class="flex items-center self-start gap-1 px-3 py-3 [grid-area:1/1] rounded-2xl rounded-br-md bg-n-brand/60 opacity-0 motion-safe:animate-showcase-blip motion-reduce:hidden"
              :style="stagger(1)"
            >
              <span
                v-for="dot in 3"
                :key="dot"
                class="rounded-full size-1.5 bg-white motion-safe:animate-bounce"
                :style="{ animationDelay: `${dot * 0.15}s` }"
              />
            </div>
            <div
              class="flex flex-col items-end gap-1 [grid-area:1/1] motion-safe:animate-showcase-rise"
              :style="stagger(4)"
            >
              <p class="px-3 py-2 text-sm rounded-2xl rounded-br-md bg-n-brand">
                {{ $t('LOGIN.SHOWCASE.REPLY.ANSWER') }}
              </p>
              <span
                class="px-1.5 py-0.5 text-[0.625rem] font-semibold rounded bg-white/15"
              >
                {{ $t('LOGIN.SHOWCASE.REPLY.BADGE') }}
              </span>
            </div>
          </div>
        </div>

        <!-- Handoff: a person takes over from the AI. -->
        <div
          v-else
          key="HANDOFF"
          class="flex flex-col gap-3 mt-auto"
          data-testid="showcase-scene-HANDOFF"
        >
          <p
            class="self-start max-w-[85%] px-3 py-2 text-sm rounded-2xl rounded-bl-md bg-white/[0.12] motion-safe:animate-showcase-rise"
            :style="stagger(0)"
          >
            {{ $t('LOGIN.SHOWCASE.HANDOFF.CUSTOMER') }}
          </p>
          <p
            class="self-center px-3 py-1 text-xs rounded-full bg-white/10 text-white/80 motion-safe:animate-showcase-rise"
            :style="stagger(1)"
          >
            {{ $t('LOGIN.SHOWCASE.HANDOFF.SYSTEM') }}
          </p>
          <div
            class="flex items-end self-end gap-2 max-w-[90%] motion-safe:animate-showcase-rise"
            :style="stagger(3)"
          >
            <p class="px-3 py-2 text-sm rounded-2xl rounded-br-md bg-n-brand">
              {{ $t('LOGIN.SHOWCASE.HANDOFF.AGENT_REPLY') }}
            </p>
            <span
              class="flex items-center justify-center text-xs font-semibold rounded-full size-7 shrink-0 bg-n-amber-9"
            >
              {{ $t('LOGIN.SHOWCASE.HANDOFF.AGENT_INITIAL') }}
            </span>
          </div>
        </div>
      </Transition>
    </div>

    <div class="flex gap-1.5">
      <span
        v-for="(scene, index) in SCENES"
        :key="scene"
        class="relative flex-1 h-0.5 overflow-hidden rounded-full bg-white/20"
      >
        <span v-if="index < current" class="absolute inset-0 bg-white/80" />
        <span
          v-else-if="index === current"
          :key="`progress-${current}`"
          class="absolute inset-y-0 left-0 w-full origin-left bg-white/80 motion-safe:animate-showcase-progress"
          :style="{ animationDuration: `${SCENE_MS}ms` }"
        />
      </span>
    </div>
  </div>
</template>
