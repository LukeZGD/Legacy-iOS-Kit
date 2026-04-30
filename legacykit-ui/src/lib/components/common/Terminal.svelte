<script lang="ts">
  import { logStore } from '../../stores/logStore.svelte';
  import { onMount, tick } from 'svelte';

  let terminalContainer: HTMLDivElement | null = null;

  // Auto-scroll logic
  $effect(() => {
    // Access logs to trigger effect when it changes
    const _logs = logStore.logs;
    
    if (terminalContainer) {
      tick().then(() => {
        if (terminalContainer) {
          terminalContainer.scrollTop = terminalContainer.scrollHeight;
        }
      });
    }
  });
</script>

<div class="terminal-wrapper flex flex-col h-full bg-[#1C1C1E] text-[#F5F5F7] rounded-md border border-[#38383A] overflow-hidden">
  <div class="terminal-header bg-[#2C2C2E] px-3 py-1.5 flex justify-between items-center text-xs text-[#98989D] border-b border-[#38383A]">
    <span>Terminal Output</span>
    <button class="hover:text-white transition-colors" onclick={() => logStore.clear()}>
      Clear
    </button>
  </div>
  <div bind:this={terminalContainer} class="terminal-content flex-1 p-3 overflow-y-auto font-mono text-[11px] leading-snug">
    {#each logStore.logs as log}
      <div class="mb-1" class:text-red-400={log.type === 'stderr'} class:text-blue-400={log.type === 'info'}>
        <span class="opacity-50 mr-2">[{new Date(log.timestamp).toLocaleTimeString()}]</span>
        <span>{log.text}</span>
      </div>
    {/each}
    {#if logStore.logs.length === 0}
      <div class="text-[#86868B] italic">No logs to display...</div>
    {/if}
  </div>
</div>
