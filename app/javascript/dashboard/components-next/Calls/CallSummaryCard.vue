<script setup>
import { computed } from 'vue';
import MessageFormatter from 'shared/helpers/MessageFormatter';
import { SUMMARY_FIELD_KIND } from './callSummary';

// The AI's summary of a call as a card: the fields it could tell apart
// (intent, result, to-dos, warnings) as label / value rows, anything else as
// rendered markdown, and the note's footer (duration, the link to the full
// recording) underneath. Markdown is rendered, never shown raw.

const props = defineProps({
  // { fields: [{ kind, label, text }], body, footer } — see ./callSummary
  summary: { type: Object, required: true },
  title: { type: String, required: true },
});

const VALUE_CLASS = {
  [SUMMARY_FIELD_KIND.TODO]: 'text-n-amber-11',
  [SUMMARY_FIELD_KIND.WARNING]: 'text-n-ruby-11',
};
const PROSE = 'prose prose-bubble max-w-none';

const render = markdown => new MessageFormatter(markdown).formattedMessage;

const fields = computed(() =>
  props.summary.fields.map((field, index) => ({
    ...field,
    key: `${field.kind}-${index}`,
    html: render(field.text),
    valueClass: VALUE_CLASS[field.kind] || '',
  }))
);
const bodyHtml = computed(() =>
  props.summary.body ? render(props.summary.body) : ''
);
const footerHtml = computed(() =>
  props.summary.footer ? render(props.summary.footer) : ''
);
</script>

<template>
  <section
    class="flex flex-col gap-3 px-4 py-3 border rounded-xl border-n-strong bg-n-alpha-1"
    data-test-id="call-summary"
  >
    <h3 class="text-sm font-medium text-n-slate-12">{{ title }}</h3>
    <dl
      v-if="fields.length"
      class="grid grid-cols-[auto_minmax(0,1fr)] gap-x-4 gap-y-2"
    >
      <template v-for="field in fields" :key="field.key">
        <dt class="text-sm leading-6 text-n-slate-11">{{ field.label }}</dt>
        <dd
          v-dompurify-html="field.html"
          :class="[PROSE, field.valueClass]"
          :data-kind="field.kind"
          data-test-id="call-summary-field"
        />
      </template>
    </dl>
    <div
      v-if="bodyHtml"
      v-dompurify-html="bodyHtml"
      :class="PROSE"
      data-test-id="call-summary-body"
    />
    <div
      v-if="footerHtml"
      v-dompurify-html="footerHtml"
      class="pt-3 text-n-slate-11 border-t border-n-weak"
      :class="PROSE"
      data-test-id="call-summary-footer"
    />
  </section>
</template>
