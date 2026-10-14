<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// What the AI had extracted when a human took over, from the call's handoff
// card: a snapshot, which is why it is titled "at takeover". The live store
// fills it in as the card arrives (see syncHandoffCard); a call nobody took
// over has none.

const props = defineProps({
  // The AI's own extraction keys, verbatim; null when there is no card.
  variables: { type: Object, default: null },
  // Said in place of the table when there is nothing to show.
  emptyText: { type: String, default: '' },
});

const { t } = useI18n();

const isMissing = value =>
  value === null || value === undefined || value === '';
const formatValue = value => {
  if (typeof value === 'boolean') {
    return value
      ? t('CONVERSATION.PATHORS_HANDOFF.YES')
      : t('CONVERSATION.PATHORS_HANDOFF.NO');
  }
  if (typeof value === 'object') return JSON.stringify(value);
  return String(value);
};

const rows = computed(() =>
  Object.entries(props.variables || {}).map(([key, value]) => ({
    key,
    isMissing: isMissing(value),
    text: isMissing(value)
      ? t('CALLS_PAGE.SHEET.NOT_CAPTURED')
      : formatValue(value),
  }))
);
</script>

<template>
  <section class="flex flex-col gap-2" data-test-id="call-variables">
    <h3 class="text-sm font-medium text-n-slate-12">
      {{ t('CALLS_PAGE.SHEET.VARIABLES') }}
    </h3>
    <dl
      v-if="rows.length"
      class="grid grid-cols-[minmax(0,2fr)_minmax(0,3fr)] overflow-hidden border rounded-xl border-n-strong text-sm"
    >
      <template v-for="row in rows" :key="row.key">
        <dt
          class="px-3 py-2 break-words border-b border-n-weak bg-n-alpha-1 text-n-slate-11 [&:nth-last-child(-n+2)]:border-b-0"
        >
          {{ row.key }}
        </dt>
        <dd
          class="px-3 py-2 break-words border-b border-n-weak [&:nth-last-child(-n+2)]:border-b-0"
          :class="row.isMissing ? 'italic text-n-slate-10' : 'text-n-slate-12'"
          data-test-id="call-variable-value"
        >
          {{ row.text }}
        </dd>
      </template>
    </dl>
    <p
      v-else
      class="text-sm text-n-slate-10"
      data-test-id="call-variables-empty"
    >
      {{ emptyText }}
    </p>
  </section>
</template>
