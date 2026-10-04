import { onBeforeUnmount, onMounted, ref } from 'vue';

const DEFAULT_TICK_MS = 1000;

/**
 * Epoch milliseconds that re-read the clock every tick, for timers that count
 * up on screen.
 *
 * Written against the app's own Vue rather than @vueuse/core's useNow:
 * @vueuse/core 12 depends on its own copy of Vue (3.5.13; the app runs
 * 3.5.12), so refs it creates are not tracked by our components' effects and
 * the timer would never re-render.
 * @param {number} [intervalMs]
 * @returns {import('vue').Ref<number>}
 */
export function useClock(intervalMs = DEFAULT_TICK_MS) {
  const now = ref(Date.now());
  let timer = null;

  onMounted(() => {
    timer = setInterval(() => {
      now.value = Date.now();
    }, intervalMs);
  });
  onBeforeUnmount(() => clearInterval(timer));

  return now;
}
