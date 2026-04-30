<script lang="ts">
  import { deviceStore } from '../../stores/deviceStore.svelte';
  
  let statusText = $derived(deviceStore.state.connected ? 'Device Connected' : 'Ready');
</script>

<footer class="h-[28px] flex items-center justify-between px-2 bg-[var(--color-bg-secondary)] border-t border-[var(--color-border)] text-[11px] text-[var(--color-text-secondary)] shrink-0">
  <div class="flex items-center gap-2">
    <div class="w-2 h-2 rounded-full {deviceStore.state.connected ? 'bg-[var(--color-success)]' : 'bg-[var(--color-text-secondary)]'}"></div>
    {statusText}
  </div>
  <div>v1.0.0</div>
</footer>
