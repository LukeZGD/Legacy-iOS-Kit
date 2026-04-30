<script lang="ts">
  import Sidebar from './lib/components/layout/Sidebar.svelte';
  import ContentArea from './lib/components/layout/ContentArea.svelte';
  import { onMount } from 'svelte';
  import { invoke } from '@tauri-apps/api/core';
  import { listen } from '@tauri-apps/api/event';
  import { deviceStore } from './lib/stores/deviceStore.svelte';
  import type { DeviceInfo } from './lib/stores/deviceStore.svelte';
  import { logStore } from './lib/stores/logStore.svelte';
  import { settingsStore } from './lib/stores/settingsStore.svelte';
  
  import './app.css';

  let pollInterval: ReturnType<typeof setInterval> | null = null;

  $effect(() => {
    const autoDetectDevice = settingsStore.autoDetectDevice;
    const pollIntervalMs = settingsStore.pollIntervalMs;

    if (pollInterval) {
      clearInterval(pollInterval);
      pollInterval = null;
    }

    if (autoDetectDevice) {
      detectDevice();
      pollInterval = setInterval(detectDevice, pollIntervalMs);
    }

    return () => {
      if (pollInterval) {
        clearInterval(pollInterval);
        pollInterval = null;
      }
    };
  });

  $effect(() => {
    const theme = settingsStore.theme;
    const root = document.documentElement;
    const darkQuery = window.matchMedia('(prefers-color-scheme: dark)');

    function applyTheme() {
      if (theme === 'system') {
        root.removeAttribute('data-theme');
      } else {
        root.dataset.theme = theme;
      }
      root.classList.toggle('dark', theme === 'dark' || (theme === 'system' && darkQuery.matches));
    }

    applyTheme();
    darkQuery.addEventListener('change', applyTheme);

    return () => darkQuery.removeEventListener('change', applyTheme);
  });

  onMount(() => {
    const unlistenLog = listen('log_event', (event: any) => {
      const { text, type } = event.payload as { text: string; type: 'stdout' | 'stderr' | 'info' };
      logStore.append(text, type);
    });

    return () => {
      unlistenLog.then(fn => fn());
    };
  });

  async function detectDevice() {
    try {
      const info = await invoke<DeviceInfo>('detect_device');
      if (info && info.connected) {
        deviceStore.updateFromBackend(info);
      } else {
        deviceStore.clearDevice();
      }
    } catch {
      deviceStore.clearDevice();
    }
  }
</script>

<div class="flex h-screen w-screen overflow-hidden bg-[var(--color-bg-primary)] text-[var(--color-text-primary)]">
  <Sidebar />
  <ContentArea />
</div>
