<script lang="ts">
  import DeviceStatus from './DeviceStatus.svelte';
  import { deviceStore } from '../../stores/deviceStore.svelte';

  // State mapped from store
  let isConnected = $derived(deviceStore.state.connected);
  let deviceName = $derived(deviceStore.state.name || 'Unknown Device');
  let deviceType = $derived(deviceStore.state.udid || 'No UDID');
  
  // These could be added to DeviceInfo model later
  let iosVersion = 'Unknown';
  let deviceMode = 'Normal';
</script>

<div class="bg-[var(--color-bg-elevated)] border border-[var(--color-border)] rounded-[var(--radius-md)] p-3 mb-6 shadow-sm transition-all duration-200 {isConnected ? 'ring-1 ring-[var(--color-accent)] ring-opacity-30' : ''}">
  <div class="flex items-center gap-2">
    <div class="text-2xl w-10 h-10 flex items-center justify-center bg-[var(--color-bg-secondary)] rounded-[var(--radius-sm)]">📱</div>
    <div class="flex-1 min-w-0">
      {#if isConnected}
        <h3 class="m-0 text-[14px] font-semibold text-[var(--color-text-primary)] truncate">{deviceName}</h3>
        <span class="text-[11px] text-[var(--color-text-secondary)] truncate block">{deviceType}</span>
      {:else}
        <h3 class="m-0 text-[14px] font-semibold text-[var(--color-text-primary)]">No Device</h3>
        <span class="text-[11px] text-[var(--color-text-secondary)]">Connect USB to begin</span>
      {/if}
    </div>
  </div>

  {#if isConnected}
    <div class="mt-3 pt-3 border-t border-[var(--color-border)]">
      <div class="flex justify-between items-center text-[12px] mb-1">
        <span class="text-[var(--color-text-secondary)]">iOS</span>
        <span class="font-medium text-[var(--color-text-primary)]">{iosVersion}</span>
      </div>
      <div class="flex justify-between items-center text-[12px]">
        <span class="text-[var(--color-text-secondary)]">Mode</span>
        <span class="font-medium text-[var(--color-text-primary)]">
          <DeviceStatus mode={deviceMode} />
        </span>
      </div>
    </div>
  {/if}
</div>
