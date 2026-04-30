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

  let pollInterval: ReturnType<typeof setInterval>;

  onMount(() => {
    detectDevice();

    pollInterval = setInterval(detectDevice, settingsStore.pollIntervalMs);

    const unlistenLog = listen('log_event', (event: any) => {
      const { text, type } = event.payload as { text: string; type: 'stdout' | 'stderr' | 'info' };
      logStore.append(text, type);
    });

    return () => {
      clearInterval(pollInterval);
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
