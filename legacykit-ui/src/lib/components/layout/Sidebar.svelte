<script lang="ts">
  import DeviceCard from '../device/DeviceCard.svelte';
  import { navigationStore } from '$lib/stores/navigationStore.svelte';
  import type { ViewName } from '$lib/stores/navigationStore.svelte';

  const navItems: { label: string; icon: string; view: ViewName }[] = [
    { label: 'Home', icon: '🏠', view: 'home' },
    { label: 'Restore', icon: '⬇️', view: 'restore' },
    { label: 'Jailbreak', icon: '🔓', view: 'jailbreak' },
    { label: 'SHSH Blobs', icon: '💾', view: 'shsh' },
    { label: 'SSH Ramdisk', icon: '🖥️', view: 'ssh-ramdisk' },
    { label: 'Apps', icon: '📱', view: 'apps' },
    { label: 'Data', icon: '📦', view: 'data' },
    { label: 'Utilities', icon: '🔧', view: 'utilities' },
    { label: 'Settings', icon: '⚙️', view: 'settings' },
  ];
</script>

<aside class="w-[240px] h-screen bg-[var(--color-bg-sidebar)] border-r border-[var(--color-border)] flex flex-col shrink-0 backdrop-blur-xl" data-tauri-drag-region>
  <div class="flex flex-col h-full p-4 pt-12">
    <DeviceCard />
    
    <nav class="mt-6 flex-1 overflow-y-auto">
      <ul class="flex flex-col gap-1 m-0 p-0 list-none">
        {#each navItems as item}
          <li>
            <button
              class="w-full px-3 py-2 rounded-md text-[14px] cursor-pointer transition-colors duration-100 flex items-center gap-3 border-0 bg-transparent text-left {navigationStore.currentView === item.view ? 'bg-[var(--color-accent)]! text-white font-medium' : 'text-[var(--color-text-primary)] hover:bg-black/5 dark:hover:bg-white/10'}"
              onclick={() => navigationStore.navigate(item.view)}
            >
              <span class="text-lg leading-none">{item.icon}</span>
              {item.label}
            </button>
          </li>
        {/each}
      </ul>
    </nav>
  </div>
</aside>
