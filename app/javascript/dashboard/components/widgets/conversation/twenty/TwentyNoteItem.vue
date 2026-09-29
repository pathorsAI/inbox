<script setup>
import { computed } from 'vue';
import { getUnixTime, parseISO } from 'date-fns';
import { dynamicTime } from 'shared/helpers/timeHelper';

const props = defineProps({
  note: {
    type: Object,
    required: true,
  },
});

const excerptLines = computed(() => (props.note.excerpt || '').split('\n'));

// An untitled note is headed by its first line, so the body only repeats what
// the heading has not already shown.
const heading = computed(() => props.note.title || excerptLines.value[0]);

const body = computed(() =>
  props.note.title ? props.note.excerpt : excerptLines.value.slice(1).join('\n')
);

const timeAgo = computed(() =>
  dynamicTime(getUnixTime(parseISO(props.note.created_at)))
);
</script>

<template>
  <li class="flex flex-col gap-0.5">
    <a
      :href="note.url"
      :title="heading"
      target="_blank"
      rel="noopener noreferrer"
      class="text-sm font-medium truncate text-n-slate-12 hover:underline"
    >
      {{ heading || $t('CONVERSATION_SIDEBAR.TWENTY.UNTITLED_NOTE') }}
    </a>
    <p
      v-if="body"
      class="mb-0 text-sm whitespace-pre-line text-n-slate-11 line-clamp-2"
    >
      {{ body }}
    </p>
    <p class="flex items-center gap-1.5 mb-0 text-xs text-n-slate-10">
      <span v-if="note.author" class="truncate">{{ note.author }}</span>
      <span v-if="note.author">·</span>
      <span class="flex-shrink-0">{{ timeAgo }}</span>
    </p>
  </li>
</template>
