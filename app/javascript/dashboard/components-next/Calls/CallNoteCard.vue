<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import MessageFormatter from 'shared/helpers/MessageFormatter';
import { messageStamp } from 'shared/helpers/timeHelper';

// One private note of a call, its markdown rendered like the conversation
// renders it.

const props = defineProps({
  // A raw (snake_case) private message.
  note: { type: Object, required: true },
});

const NOTE_TIME_FORMAT = 'MM/dd HH:mm';

const { t } = useI18n();

const byline = computed(() =>
  t('CALLS_PAGE.SHEET.NOTES.BYLINE', {
    author:
      props.note.sender?.available_name ||
      props.note.sender?.name ||
      t('CALLS_PAGE.SHEET.NOTES.UNKNOWN_AUTHOR'),
    time: messageStamp(props.note.created_at, NOTE_TIME_FORMAT),
  })
);
const html = computed(
  () => new MessageFormatter(props.note.content).formattedMessage
);
</script>

<template>
  <article
    class="flex flex-col gap-1 px-3 py-2.5 border rounded-xl bg-n-amber-2 border-n-amber-5"
    data-test-id="call-note"
  >
    <span class="text-xs text-n-slate-11">{{ byline }}</span>
    <div v-dompurify-html="html" class="prose prose-bubble max-w-none" />
  </article>
</template>
