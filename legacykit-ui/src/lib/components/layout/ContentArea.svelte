<script lang="ts">
  import Toolbar from './Toolbar.svelte';
  import StatusBar from './StatusBar.svelte';
  import ActionPanel from '../actions/ActionPanel.svelte';
  import Terminal from '../common/Terminal.svelte';
  import { navigationStore } from '$lib/stores/navigationStore.svelte';
  import { settingsStore } from '$lib/stores/settingsStore.svelte';

  import HomeView from '$lib/views/HomeView.svelte';
  import RestoreView from '$lib/views/RestoreView.svelte';
  import JailbreakView from '$lib/views/JailbreakView.svelte';
  import SHSHView from '$lib/views/SHSHView.svelte';
  import SSHRamdiskView from '$lib/views/SSHRamdiskView.svelte';
  import AppsView from '$lib/views/AppsView.svelte';
  import DataView from '$lib/views/DataView.svelte';
  import UtilitiesView from '$lib/views/UtilitiesView.svelte';
  import SettingsView from '$lib/views/SettingsView.svelte';
</script>

<main class="flex-1 flex flex-col h-screen bg-[var(--color-bg-primary)]">
  <Toolbar />
  
  <div class="flex-1 overflow-hidden flex flex-col p-6">
    <div class="flex-1 flex justify-center overflow-y-auto mb-6">
      <div class="w-full max-w-[800px] flex flex-col gap-8">
        {#if navigationStore.currentView === 'home'}
          <HomeView />
        {:else if navigationStore.currentView === 'restore'}
          <RestoreView />
        {:else if navigationStore.currentView === 'jailbreak'}
          <JailbreakView />
        {:else if navigationStore.currentView === 'shsh'}
          <SHSHView />
        {:else if navigationStore.currentView === 'ssh-ramdisk'}
          <SSHRamdiskView />
        {:else if navigationStore.currentView === 'apps'}
          <AppsView />
        {:else if navigationStore.currentView === 'data'}
          <DataView />
        {:else if navigationStore.currentView === 'utilities'}
          <UtilitiesView />
        {:else if navigationStore.currentView === 'settings'}
          <SettingsView />
        {/if}
      </div>
    </div>
    
    {#if settingsStore.terminalVisible}
      <div class="shrink-0" style={`height: ${settingsStore.terminalHeight}px`}>
        <Terminal />
      </div>
    {/if}
  </div>
  
  <StatusBar />
</main>
