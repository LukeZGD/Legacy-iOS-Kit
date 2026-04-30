<script lang="ts">
  import { invoke } from '@tauri-apps/api/core';
  import { listen, type UnlistenFn } from '@tauri-apps/api/event';
  import { onDestroy } from 'svelte';
  import { actionStore } from '../../stores/actionStore.svelte';
  import { logStore } from '../../stores/logStore.svelte';

  let unlistenLogs: UnlistenFn | null = null;
  let unlistenFinished: UnlistenFn | null = null;

  async function runCommand(name: string, command: string, args: string[], eventName: string) {
    if (actionStore.status === 'running') return;

    actionStore.start(name);
    logStore.clear();
    logStore.append(`Executing ${name}...`, 'info');

    try {
      if (unlistenLogs) unlistenLogs();
      if (unlistenFinished) unlistenFinished();

      unlistenLogs = await listen<string>(eventName, (event) => {
        logStore.append(event.payload, 'stdout');
      });

      unlistenFinished = await listen<string>(`${eventName}_finished`, () => {
        actionStore.success();
        logStore.append(`Finished ${name}`, 'info');
        cleanupListeners();
      });

      await invoke(command, { args, eventName });
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : String(err);
      actionStore.fail(errorMsg);
      logStore.append(`Error: ${errorMsg}`, 'stderr');
      cleanupListeners();
    }
  }

  function cleanupListeners() {
    if (unlistenLogs) {
      unlistenLogs();
      unlistenLogs = null;
    }
    if (unlistenFinished) {
      unlistenFinished();
      unlistenFinished = null;
    }
  }

  onDestroy(() => {
    cleanupListeners();
  });

  const getDeviceInfo = () => runCommand('Get Device Info', 'execute_idevice_info', [], 'idevice_info_logs');
  const enterRecovery = () => runCommand('Enter Recovery', 'execute_irecovery', ['-n'], 'irecovery_logs');
</script>

<div class="bg-[var(--color-bg-secondary)] border border-[var(--color-border)] rounded-[var(--radius-md)] p-6 mb-6">
  <h2 class="text-[16px] font-semibold mb-4 text-[var(--color-text-primary)]">Quick Actions</h2>
  
  <div class="flex gap-4 flex-wrap">
    <button 
      class="px-5 py-2 rounded-[var(--radius-sm)] text-[14px] font-medium cursor-pointer border border-transparent transition-all duration-200 bg-[var(--color-accent)] text-white hover:brightness-110 disabled:opacity-50 disabled:cursor-not-allowed" 
      onclick={getDeviceInfo}
      disabled={actionStore.status === 'running'}
    >
      Get Device Info
    </button>
    <button 
      class="px-5 py-2 rounded-[var(--radius-sm)] text-[14px] font-medium cursor-pointer border border-[var(--color-border)] transition-all duration-200 bg-transparent text-[var(--color-text-primary)] hover:bg-black/5 dark:hover:bg-white/10 disabled:opacity-50 disabled:cursor-not-allowed" 
      onclick={enterRecovery}
      disabled={actionStore.status === 'running'}
    >
      Enter Recovery
    </button>
  </div>

  {#if actionStore.status !== 'idle'}
    <div class="mt-4 pt-4 border-t border-[var(--color-border)]">
      {#if actionStore.status === 'running'}
        <span class="inline-block px-3 py-1 rounded-[var(--radius-sm)] text-[12px] font-medium bg-black/5 dark:bg-white/10 text-[var(--color-text-secondary)]">Running: {actionStore.currentAction}</span>
      {:else if actionStore.status === 'success'}
        <span class="inline-block px-3 py-1 rounded-[var(--radius-sm)] text-[12px] font-medium bg-green-500/10 text-green-600 dark:text-green-400">Success: {actionStore.currentAction}</span>
      {:else if actionStore.status === 'error'}
        <span class="inline-block px-3 py-1 rounded-[var(--radius-sm)] text-[12px] font-medium bg-red-500/10 text-red-600 dark:text-red-400">Failed: {actionStore.currentAction}</span>
        <div class="mt-2 text-[12px] text-red-600 dark:text-red-400">{actionStore.error}</div>
      {/if}
    </div>
  {/if}
</div>
