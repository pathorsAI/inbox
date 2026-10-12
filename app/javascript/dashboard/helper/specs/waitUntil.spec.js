import { nextTick, ref } from 'vue';
import { waitUntil } from '../waitUntil';

describe('waitUntil', () => {
  it('resolves right away when the condition already holds', async () => {
    await expect(waitUntil(() => true)).resolves.toBeUndefined();
  });

  it('waits for an app ref that starts out false', async () => {
    const fetching = ref(true);
    let resolved = false;
    const promise = waitUntil(() => !fetching.value).then(() => {
      resolved = true;
    });

    await nextTick();
    expect(resolved).toBe(false);

    fetching.value = false;
    await promise;
    expect(resolved).toBe(true);
  });
});
