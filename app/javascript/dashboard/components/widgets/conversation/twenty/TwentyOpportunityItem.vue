<script setup>
import { computed } from 'vue';
import { format, parseISO } from 'date-fns';
import { useLocale } from 'shared/composables/useLocale';
import StageChip from 'dashboard/components-next/label/Label.vue';

const props = defineProps({
  opportunity: {
    type: Object,
    required: true,
  },
});

// Twenty's select-option colours mapped onto the dashboard label palette.
// Anything not listed (gray, or a colour Twenty adds later) renders as slate.
const STAGE_COLORS = {
  red: 'ruby',
  ruby: 'ruby',
  pink: 'ruby',
  orange: 'amber',
  amber: 'amber',
  yellow: 'amber',
  lime: 'teal',
  green: 'teal',
  turquoise: 'teal',
  sky: 'blue',
  blue: 'blue',
  purple: 'iris',
};

const { resolvedLocale } = useLocale();

const stageColor = computed(
  () => STAGE_COLORS[props.opportunity.stage?.color] || 'slate'
);

const formattedAmount = computed(() => {
  const { amount } = props.opportunity;
  if (!amount) return '';
  return new Intl.NumberFormat(resolvedLocale.value, {
    style: 'currency',
    currency: amount.currency,
    maximumFractionDigits: 0,
  }).format(amount.value);
});

// close_date is a date-only string; parseISO reads it as local midnight so the
// day does not shift in timezones behind UTC.
const formattedCloseDate = computed(() => {
  const { close_date: closeDate } = props.opportunity;
  return closeDate ? format(parseISO(closeDate), 'MMM d, yyyy') : '';
});
</script>

<template>
  <div class="flex flex-col gap-1">
    <div class="flex items-center justify-between min-w-0 gap-2">
      <a
        :href="opportunity.url"
        :title="opportunity.name"
        target="_blank"
        rel="noopener noreferrer"
        class="text-sm font-medium truncate text-n-slate-12 hover:underline"
      >
        {{ opportunity.name }}
      </a>
      <StageChip
        v-if="opportunity.stage"
        :label="opportunity.stage.label"
        :color="stageColor"
        compact
      />
    </div>
    <div
      v-if="formattedAmount || formattedCloseDate"
      class="flex items-center gap-1.5 text-sm text-n-slate-11"
    >
      <span v-if="formattedAmount" class="tabular-nums">
        {{ formattedAmount }}
      </span>
      <span v-if="formattedAmount && formattedCloseDate">·</span>
      <span v-if="formattedCloseDate">
        {{
          $t('CONVERSATION_SIDEBAR.TWENTY.CLOSE_DATE', {
            date: formattedCloseDate,
          })
        }}
      </span>
    </div>
  </div>
</template>
