<script setup>
import { computed, ref, toRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useCallNotes } from 'dashboard/composables/useCallNotes';
import { messageStamp } from 'shared/helpers/timeHelper';
import Button from 'dashboard/components-next/button/Button.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

// The call's private notes. They are written to its conversation, which is
// where a colleague taking the call back over, or calling back, finds them.

const props = defineProps({
  // The display id of the call's conversation.
  conversationId: { type: Number, default: null },
});

const NOTE_MAX_LENGTH = 2000;
const NOTE_TIME_FORMAT = 'MM/dd HH:mm';

const { t } = useI18n();
const { notes, isLoading, hasLoadError, isSaving, create } = useCallNotes(
  toRef(props, 'conversationId')
);

const draft = ref('');
const canSave = computed(
  () => !!draft.value.trim() && !isSaving.value && !!props.conversationId
);

const author = note =>
  note.sender?.available_name ||
  note.sender?.name ||
  t('CALLS_PAGE.SHEET.NOTES.UNKNOWN_AUTHOR');

const save = async () => {
  if (!canSave.value) return;
  const saved = await create(draft.value.trim());
  if (saved) {
    draft.value = '';
  } else {
    useAlert(t('CALLS_PAGE.SHEET.NOTES.SAVE_FAILED'));
  }
};

const onKeydown = event => {
  if (event.key !== 'Enter' || !(event.metaKey || event.ctrlKey)) return;
  event.preventDefault();
  save();
};
</script>

<template>
  <section class="flex flex-col gap-2" data-test-id="call-notes">
    <h3 class="text-xs font-medium text-n-slate-11">
      {{ t('CALLS_PAGE.SHEET.NOTES.TITLE') }}
    </h3>
    <p v-if="isLoading" class="text-sm text-n-slate-10">
      {{ t('CALLS_PAGE.SHEET.NOTES.LOADING') }}
    </p>
    <p v-else-if="hasLoadError" class="text-sm text-n-ruby-11">
      {{ t('CALLS_PAGE.SHEET.NOTES.LOAD_FAILED') }}
    </p>
    <p
      v-else-if="!notes.length"
      class="text-sm text-n-slate-10"
      data-test-id="call-notes-empty"
    >
      {{ t('CALLS_PAGE.SHEET.NOTES.EMPTY') }}
    </p>
    <ol v-else class="flex flex-col gap-2">
      <li
        v-for="note in notes"
        :key="note.id"
        class="flex flex-col gap-0.5 px-2.5 py-2 rounded-lg bg-n-amber-2"
        data-test-id="call-note"
      >
        <span class="text-xs text-n-slate-11">
          {{
            t('CALLS_PAGE.SHEET.NOTES.BYLINE', {
              author: author(note),
              time: messageStamp(note.created_at, NOTE_TIME_FORMAT),
            })
          }}
        </span>
        <p class="text-sm break-words whitespace-pre-line text-n-slate-12">
          {{ note.content }}
        </p>
      </li>
    </ol>
    <TextArea
      v-model="draft"
      :placeholder="t('CALLS_PAGE.SHEET.NOTES.PLACEHOLDER')"
      :max-length="NOTE_MAX_LENGTH"
      :disabled="!conversationId"
      auto-height
      min-height="3rem"
      data-test-id="call-note-input"
      @keydown="onKeydown"
    />
    <Button
      :label="t('CALLS_PAGE.SHEET.NOTES.ADD')"
      size="sm"
      color="slate"
      class="self-end"
      :disabled="!canSave"
      :is-loading="isSaving"
      data-test-id="call-note-save"
      @click="save"
    />
  </section>
</template>
