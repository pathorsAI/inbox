import { watch } from 'vue';

/**
 * Resolves once `getter()` is truthy — right away if it already is.
 *
 * Written against the app's own Vue rather than @vueuse/core's `until`:
 * @vueuse/core 12 depends on its own copy of Vue (3.5.13; the app runs
 * 3.5.12), so a watcher it creates never sees changes to the app's reactive
 * state and the promise would hang whenever the condition starts out false
 * (see composables/useClock.js for the same split).
 * @param {() => unknown} getter
 * @returns {Promise<void>}
 */
export function waitUntil(getter) {
  return new Promise(resolve => {
    let done = false;
    let stop = null;
    stop = watch(
      getter,
      value => {
        if (!value || done) return;
        done = true;
        // With `immediate`, the first call runs before `watch` returns.
        if (stop) stop();
        resolve();
      },
      { immediate: true }
    );
    if (done) stop();
  });
}
