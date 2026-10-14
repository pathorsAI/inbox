<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import CallNoteCard from './CallNoteCard.vue';

// The call's private notes and a box to add one. The sheet owns the notes
// (useCallNotes): its summary and quick tags read and write the same list.
// They are written to the call's conversation, which is where a colleague
// taking the call back over, or calling back, finds them.

const props = defineProps({
  notes: { type: Array, default: () => [] },
  isLoading: { type: Boolean, default: false },
  hasLoadError: { type: Boolean, default: false },
  isSaving: { type: Boolean, default: false },
  // False for a call without a conversation to write to.
  canWrite: { type: Boolean, default: false },
  // useCallNotes' create: (content) => Promise<boolean>
  create: { type: Function, required: true },
});

const NOTE_MAX_LENGTH = 2000;

const { t } = useI18n();

const draft = ref('');
const canSave = computed(
  () => !!draft.value.trim() && !props.isSaving && props.canWrite
);

const save = async () => {
  if (!canSave.value) return;
  const saved = await props.create(draft.value.trim());
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
  <section class="flex flex-col gap-3" data-test-id="call-notes">
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
      <li v-for="note in notes" :key="note.id">
        <CallNoteCard :note="note" />
      </li>
    </ol>
    <TextArea
      v-model="draft"
      :placeholder="t('CALLS_PAGE.SHEET.NOTES.PLACEHOLDER')"
      :max-length="NOTE_MAX_LENGTH"
      show-character-count
      :disabled="!canWrite"
      auto-height
      min-height="4rem"
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
