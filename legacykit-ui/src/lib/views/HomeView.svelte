<script lang="ts">
  import { deviceStore } from '../stores/deviceStore.svelte';
  import { navigationStore } from '../stores/navigationStore.svelte';
  import type { ViewName } from '../stores/navigationStore.svelte';
  import heroImage from '../../assets/hero.png';

  const quickActions: { label: string; icon: string; view: ViewName; description: string }[] = [
    { label: 'Restore', icon: '⬇️', view: 'restore', description: 'Restore & downgrade iOS' },
    { label: 'Jailbreak', icon: '🔓', view: 'jailbreak', description: 'Jailbreak legacy devices' },
    { label: 'SHSH Blobs', icon: '💾', view: 'shsh', description: 'Save & manage blobs' },
    { label: 'SSH Ramdisk', icon: '🖥️', view: 'ssh-ramdisk', description: 'Boot SSH ramdisk' },
  ];
</script>

<div class="home-view">
  <div class="hero-section">
    <img src={heroImage} alt="LegacyKit" class="hero-image" />
    <div class="hero-text">
      <h1>LegacyKit</h1>
      <p class="subtitle">The all-in-one toolkit for legacy iOS devices</p>
    </div>
  </div>

  <div class="device-card">
    {#if deviceStore.state.connected}
      <div class="device-connected">
        <span class="device-indicator connected"></span>
        <div class="device-info">
          <h3>{deviceStore.state.name ?? 'Unknown Device'}</h3>
          <p>
            {deviceStore.state.product_type ?? 'Unknown'} &middot;
            iOS {deviceStore.state.ios_version ?? '?'} &middot;
            {deviceStore.state.mode}
          </p>
        </div>
      </div>
    {:else}
      <div class="device-disconnected">
        <span class="device-indicator disconnected"></span>
        <div class="device-info">
          <h3>No Device Connected</h3>
          <p>Connect a device to get started</p>
        </div>
      </div>
    {/if}
  </div>

  <div class="quick-actions">
    <h2>Quick Actions</h2>
    <div class="actions-grid">
      {#each quickActions as action}
        <button
          class="action-card"
          onclick={() => navigationStore.navigate(action.view)}
        >
          <span class="action-icon">{action.icon}</span>
          <span class="action-label">{action.label}</span>
          <span class="action-description">{action.description}</span>
        </button>
      {/each}
    </div>
  </div>
</div>

<style>
  .home-view {
    padding: var(--spacing-lg);
    max-width: 720px;
    margin: 0 auto;
  }

  .hero-section {
    display: flex;
    flex-direction: column;
    align-items: center;
    text-align: center;
    margin-bottom: var(--spacing-xl);
  }

  .hero-image {
    width: 128px;
    height: 128px;
    object-fit: contain;
    margin-bottom: var(--spacing-md);
  }

  .hero-text h1 {
    font-size: 2rem;
    font-weight: 700;
    color: var(--color-text-primary);
    margin-bottom: var(--spacing-xs);
  }

  .subtitle {
    color: var(--color-text-secondary);
    font-size: 1rem;
    line-height: 1.5;
  }

  .device-card {
    background: var(--color-bg-secondary);
    border-radius: var(--radius-lg);
    border: 1px solid var(--color-border);
    padding: var(--spacing-md);
    margin-bottom: var(--spacing-xl);
  }

  .device-connected,
  .device-disconnected {
    display: flex;
    align-items: center;
    gap: var(--spacing-md);
  }

  .device-indicator {
    width: 10px;
    height: 10px;
    border-radius: 50%;
    flex-shrink: 0;
  }

  .device-indicator.connected {
    background: var(--color-success);
    box-shadow: 0 0 6px var(--color-success);
  }

  .device-indicator.disconnected {
    background: var(--color-text-secondary);
  }

  .device-info h3 {
    font-size: 0.938rem;
    font-weight: 600;
    color: var(--color-text-primary);
    margin-bottom: 2px;
  }

  .device-info p {
    font-size: 0.813rem;
    color: var(--color-text-secondary);
    margin: 0;
  }

  .quick-actions h2 {
    font-size: 1.125rem;
    font-weight: 600;
    color: var(--color-text-primary);
    margin-bottom: var(--spacing-md);
  }

  .actions-grid {
    display: grid;
    grid-template-columns: repeat(2, 1fr);
    gap: var(--spacing-sm);
  }

  .action-card {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--spacing-xs);
    padding: var(--spacing-lg) var(--spacing-md);
    background: var(--color-bg-secondary);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
    cursor: pointer;
    transition: all 0.15s ease;
    text-align: center;
    font-family: inherit;
  }

  .action-card:hover {
    border-color: var(--color-accent);
    background: var(--color-bg-elevated);
    transform: translateY(-1px);
  }

  .action-icon {
    font-size: 1.75rem;
  }

  .action-label {
    font-size: 0.938rem;
    font-weight: 600;
    color: var(--color-text-primary);
  }

  .action-description {
    font-size: 0.75rem;
    color: var(--color-text-secondary);
    line-height: 1.4;
  }
</style>
