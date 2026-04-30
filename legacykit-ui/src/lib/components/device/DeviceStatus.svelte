<script lang="ts">
  let { mode = 'Normal' }: { mode?: 'Normal' | 'Recovery' | 'DFU' | 'kDFU' | 'pwnDFU' | 'WTF' } = $props();

  // Determine status color based on mode
  let statusColor = $derived(getStatusColor(mode));

  function getStatusColor(m: string): string {
    switch(m) {
      case 'Normal': return 'var(--color-success)';
      case 'Recovery': return 'var(--color-warning)';
      case 'DFU': 
      case 'kDFU': 
      case 'pwnDFU': return 'var(--color-danger)';
      default: return 'var(--color-text-secondary)';
    }
  }
</script>

<div class="status-indicator">
  <span class="dot" style="background-color: {statusColor}"></span>
  <span class="mode-text">{mode}</span>
</div>

<style>
  .status-indicator {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    background-color: var(--color-bg-secondary);
    padding: 2px 6px;
    border-radius: 10px;
  }

  .dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    display: inline-block;
  }

  .mode-text {
    font-size: 11px;
    font-weight: 500;
  }
</style>
