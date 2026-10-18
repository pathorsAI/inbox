<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';

// The transcript window the Pathors backend pushes on every AI turn (kept on
// the call after it ends), as a chat: the caller's lines on the left, the
// AI's on the right (like the hand-off card), and the call's events (help
// requested, transfer, human left) as dividers. It fills the height its
// parent gives it and is the only thing in it that scrolls. The sheet's tab
// names it, so it carries no title of its own.

const props = defineProps({
  // `live.transcript` entries: { kind: 'message', role, content, interrupted }
  // (role is 'user' or 'assistant') or { kind: 'system', code, text }.
  entries: { type: Array, default: () => [] },
  // Bumps on every turn; a live call follows it to the bottom.
  seq: { type: Number, default: 0 },
  isLive: { type: Boolean, default: false },
});

// How close to the bottom still counts as "following along", so a new line
// keeps the view pinned there instead of leaving the reader behind. Further
// up, the reader is reading back: stop following and offer a way back.
const STICK_TO_BOTTOM_PX = 40;
const ROLE_ASSISTANT = 'assistant';
const KIND_SYSTEM = 'system';

const SYSTEM_CODE_CLASS = {
  takeover_requested: 'text-n-ruby-11 before:bg-n-ruby-6 after:bg-n-ruby-6',
  transfer_failed: 'text-n-ruby-11 before:bg-n-ruby-6 after:bg-n-ruby-6',
  transfer_started: 'text-n-blue-11 before:bg-n-blue-6 after:bg-n-blue-6',
  // A dial withdrawn because a human took the call while it rang — a hand-off, not a failure.
  transfer_cancelled: 'text-n-blue-11 before:bg-n-blue-6 after:bg-n-blue-6',
  transfer_connected: 'text-n-blue-11 before:bg-n-blue-6 after:bg-n-blue-6',
  human_left: 'text-n-blue-11 before:bg-n-blue-6 after:bg-n-blue-6',
};
const DEFAULT_SYSTEM_CLASS = 'text-n-slate-10 before:bg-n-weak after:bg-n-weak';

const { t } = useI18n();

// The speaker is named only when it changes: a run of lines from the same
// side shares one name, and a divider starts a new run.
const rows = computed(() =>
  props.entries.map((entry, index) => {
    const previous = props.entries[index - 1];
    const isSystem = entry.kind === KIND_SYSTEM;
    return {
      ...entry,
      key: `${entry.at ?? ''}-${index}`,
      isSystem,
      isAssistant: entry.role === ROLE_ASSISTANT,
      showRole:
        !isSystem &&
        (!previous ||
          previous.kind === KIND_SYSTEM ||
          previous.role !== entry.role),
      systemClass: SYSTEM_CODE_CLASS[entry.code] || DEFAULT_SYSTEM_CLASS,
    };
  })
);

const listRef = ref(null);
const isFollowing = ref(true);

const onScroll = () => {
  const el = listRef.value;
  if (!el) return;
  isFollowing.value =
    el.scrollHeight - el.scrollTop - el.clientHeight <= STICK_TO_BOTTOM_PX;
};

const scrollToBottom = () => {
  const el = listRef.value;
  if (el) el.scrollTop = el.scrollHeight;
};

const showJumpToLatest = computed(
  () => props.isLive && !isFollowing.value && rows.value.length > 0
);

const jumpToLatest = () => {
  isFollowing.value = true;
  scrollToBottom();
};

watch(
  () => props.seq,
  async () => {
    if (!props.isLive || !isFollowing.value) return;
    await nextTick();
    scrollToBottom();
  },
  { immediate: true, flush: 'post' }
);
</script>

<template>
  <section class="relative flex flex-col min-h-0">
    <button
      v-if="showJumpToLatest"
      type="button"
      class="absolute z-10 inline-flex items-center gap-1 h-7 px-3 mx-auto text-xs rounded-full shadow-sm inset-x-0 bottom-3 w-fit outline outline-1 -outline-offset-1 outline-n-strong bg-n-surface-1 text-n-slate-12 hover:bg-n-alpha-2"
      data-test-id="call-transcript-jump"
      @click="jumpToLatest"
    >
      {{ t('CALLS_PAGE.SHEET.JUMP_TO_LATEST') }}
      <Icon icon="i-lucide-arrow-down" class="size-3.5" />
    </button>
    <ol
      v-if="rows.length"
      ref="listRef"
      class="flex flex-col flex-1 min-h-0 gap-3 px-5 py-4 overflow-y-auto"
      data-test-id="call-transcript"
      @scroll="onScroll"
    >
      <template v-for="row in rows" :key="row.key">
        <li
          v-if="row.isSystem"
          class="flex items-center gap-2 text-xs text-center before:flex-1 before:h-px after:flex-1 after:h-px"
          :class="row.systemClass"
          :data-code="row.code"
          data-test-id="call-transcript-system"
        >
          {{ row.text }}
        </li>
        <li
          v-else
          class="flex flex-col gap-0.5"
          :class="row.isAssistant ? 'items-end' : 'items-start'"
          :data-test-id="
            row.isAssistant ? 'call-transcript-ai' : 'call-transcript-caller'
          "
        >
          <span
            v-if="row.showRole"
            class="text-xs text-n-slate-11"
            data-test-id="call-transcript-role"
          >
            {{
              row.isAssistant
                ? t('CALLS_PAGE.SHEET.ROLE_AI')
                : t('CALLS_PAGE.SHEET.ROLE_CALLER')
            }}
          </span>
          <!-- An outline, not a border, so a cut-off line keeps its size. -->
          <p
            class="max-w-[82%] px-3 py-2 text-sm leading-relaxed whitespace-pre-wrap break-words rounded-2xl text-n-slate-12"
            :class="[
              row.isAssistant
                ? 'bg-n-blue-3 rounded-ee-md'
                : 'bg-n-slate-3 rounded-es-md',
              {
                'outline-dashed outline-1 outline-n-amber-9 -outline-offset-1':
                  row.interrupted,
              },
            ]"
          >
            {{ row.content }}
          </p>
          <span
            v-if="row.interrupted"
            class="px-1.5 text-xs rounded-full text-n-amber-11 bg-n-amber-3"
            data-test-id="call-transcript-interrupted"
          >
            {{ t('CALLS_PAGE.SHEET.INTERRUPTED') }}
          </span>
        </li>
      </template>
    </ol>
    <p v-else class="px-5 py-4 text-sm text-n-slate-10">
      {{ t('CALLS_PAGE.SHEET.NO_TRANSCRIPT') }}
    </p>
  </section>
</template>
