<script setup>
import { useI18n } from 'vue-i18n';

// The call's three numbers — duration, AI turns, interruptions — each with
// the limit past which the call turns amber (PATHORS_ALERT_THRESHOLDS).

defineProps({
  // [{ key, label, value, limit, isOver }]
  metrics: { type: Array, required: true },
  label: { type: String, required: true },
});

const { t } = useI18n();
</script>

<template>
  <dl
    class="grid grid-cols-3 gap-2"
    :aria-label="label"
    data-test-id="call-metrics"
  >
    <div
      v-for="metric in metrics"
      :key="metric.key"
      class="flex flex-col-reverse gap-0.5 px-3 py-2 border rounded-xl bg-n-alpha-1"
      :class="metric.isOver ? 'border-n-amber-7' : 'border-n-strong'"
      :data-metric="metric.key"
      :data-over="metric.isOver"
    >
      <dt
        class="flex flex-wrap justify-between gap-x-2 text-xs text-n-slate-11"
      >
        <span>{{ metric.label }}</span>
        <span class="tabular-nums">
          {{ t('CALLS_PAGE.SHEET.METRIC_LIMIT', { limit: metric.limit }) }}
        </span>
      </dt>
      <dd
        class="text-lg font-semibold tabular-nums"
        :class="metric.isOver ? 'text-n-amber-11' : 'text-n-slate-12'"
      >
        {{ metric.value }}
        <span v-if="metric.isOver" class="sr-only">
          {{ t('CALLS_PAGE.SHEET.METRIC_OVER') }}
        </span>
      </dd>
    </div>
  </dl>
</template>
