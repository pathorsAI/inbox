<script setup>
import { ref } from 'vue';
import Collapsible from './Collapsible.vue';

const isOpen = ref(false);
const isDisabledOpen = ref(false);
</script>

<template>
  <Story title="Components/Collapsible" :layout="{ type: 'grid', width: 420 }">
    <Variant title="Default">
      <div class="p-4 bg-n-background">
        <Collapsible v-model:open="isOpen">
          <template #trigger="{ chevronClass }">
            <div
              class="flex items-center justify-between gap-2 p-2 rounded-lg hover:bg-n-alpha-2"
            >
              <span class="text-sm font-medium text-n-slate-12">Inboxes</span>
              <span :class="chevronClass" />
            </div>
          </template>
          <ul class="px-2 pb-2 text-sm list-none text-n-slate-11">
            <li class="p-2">Website</li>
            <li class="p-2">Email</li>
            <li class="p-2">WhatsApp</li>
          </ul>
        </Collapsible>
        <p class="mt-2 text-xs text-n-slate-10">Open: {{ isOpen }}</p>
      </div>
    </Variant>

    <Variant title="Open by default">
      <div class="p-4 bg-n-background">
        <Collapsible open>
          <template #trigger="{ open, chevronClass }">
            <div class="flex items-center justify-between gap-2 p-2">
              <span class="text-sm font-medium text-n-slate-12">
                {{ open ? 'Hide details' : 'Show details' }}
              </span>
              <span :class="chevronClass" />
            </div>
          </template>
          <p class="px-2 pb-2 mb-0 text-sm text-n-slate-11">
            The panel animates with grid-template-rows, so no height is
            measured.
          </p>
        </Collapsible>
      </div>
    </Variant>

    <Variant title="Disabled">
      <div class="p-4 bg-n-background">
        <Collapsible v-model:open="isDisabledOpen" disabled>
          <template #trigger="{ chevronClass }">
            <div
              class="flex items-center justify-between gap-2 p-2 opacity-50 cursor-not-allowed"
            >
              <span class="text-sm font-medium text-n-slate-12">Archived</span>
              <span :class="chevronClass" />
            </div>
          </template>
          <p class="px-2 pb-2 mb-0 text-sm text-n-slate-11">Never reachable.</p>
        </Collapsible>
      </div>
    </Variant>
  </Story>
</template>
