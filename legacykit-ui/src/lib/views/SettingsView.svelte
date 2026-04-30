<script lang="ts">
  import { settingsStore } from '$lib/stores/settingsStore.svelte';

  function handleThemeChange(event: Event) {
    const target = event.target as HTMLSelectElement;
    settingsStore.setTheme(target.value as 'system' | 'light' | 'dark');
  }

  function handleTerminalToggle() {
    settingsStore.toggleTerminal();
  }

  function handleAutoDetectToggle() {
    settingsStore.autoDetectDevice = !settingsStore.autoDetectDevice;
  }

  function handleTerminalHeightChange(event: Event) {
    const target = event.target as HTMLInputElement;
    settingsStore.setTerminalHeight(Number(target.value));
  }

  function handlePollIntervalChange(event: Event) {
    const target = event.target as HTMLInputElement;
    settingsStore.setPollInterval(Number(target.value));
  }
</script>

<div class="view">
  <div class="view-header">
    <h1>Settings</h1>
  </div>

  <div class="settings-group">
    <h3>Appearance</h3>
    <div class="setting-row">
      <div class="setting-info">
        <label for="theme-select">Theme</label>
        <span class="setting-hint">Choose how LegacyKit appears</span>
      </div>
      <select
        id="theme-select"
        value={settingsStore.theme}
        onchange={handleThemeChange}
      >
        <option value="system">System</option>
        <option value="light">Light</option>
        <option value="dark">Dark</option>
      </select>
    </div>
  </div>

  <div class="settings-group">
    <h3>Terminal</h3>
    <div class="setting-row">
      <div class="setting-info">
        <label for="terminal-toggle">Show Terminal</label>
        <span class="setting-hint">Display the log terminal panel</span>
      </div>
      <label class="toggle">
        <input
          id="terminal-toggle"
          type="checkbox"
          checked={settingsStore.terminalVisible}
          onchange={handleTerminalToggle}
        />
        <span class="toggle-slider"></span>
      </label>
    </div>
    <div class="setting-row">
      <div class="setting-info">
        <label for="terminal-height">Terminal Height</label>
        <span class="setting-hint">Adjust the terminal panel size</span>
      </div>
      <div class="range-control">
        <input
          id="terminal-height"
          type="range"
          min="100"
          max="600"
          step="20"
          value={settingsStore.terminalHeight}
          oninput={handleTerminalHeightChange}
        />
        <span>{settingsStore.terminalHeight}px</span>
      </div>
    </div>
  </div>

  <div class="settings-group">
    <h3>Device Detection</h3>
    <div class="setting-row">
      <div class="setting-info">
        <label for="auto-detect-toggle">Auto-Detect Device</label>
        <span class="setting-hint">Automatically detect connected devices</span>
      </div>
      <label class="toggle">
        <input
          id="auto-detect-toggle"
          type="checkbox"
          checked={settingsStore.autoDetectDevice}
          onchange={handleAutoDetectToggle}
        />
        <span class="toggle-slider"></span>
      </label>
    </div>
    <div class="setting-row">
      <div class="setting-info">
        <label for="poll-interval">Poll Interval (ms)</label>
        <span class="setting-hint">How often to check for device changes (min: 1000ms)</span>
      </div>
      <input
        id="poll-interval"
        type="number"
        min="1000"
        step="500"
        value={settingsStore.pollIntervalMs}
        onchange={handlePollIntervalChange}
      />
    </div>
  </div>

  <div class="settings-group about-section">
    <h3>About</h3>
    <div class="about-card">
      <p class="app-name">LegacyKit <span class="version">v0.1.0</span></p>
      <p class="about-description">A modern toolkit for managing legacy iOS devices. Restore, jailbreak, manage SHSH blobs, and more — all from a single native application.</p>
    </div>
  </div>
</div>

<style>
  .view { padding: var(--spacing-xl); max-width: 640px; }
  .view-header { margin-bottom: var(--spacing-lg); }
  .view-header h1 { font-size: 1.5rem; font-weight: 700; color: var(--color-text-primary); margin: 0; }

  .settings-group {
    margin-bottom: var(--spacing-lg);
  }
  .settings-group h3 {
    font-size: 0.8rem;
    font-weight: 600;
    color: var(--color-text-secondary);
    text-transform: uppercase;
    letter-spacing: 0.05em;
    margin-bottom: var(--spacing-sm);
  }

  .setting-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: var(--spacing-sm) var(--spacing-md);
    background: var(--color-bg-secondary);
    border-radius: var(--radius-md);
    margin-bottom: 1px;
  }
  .setting-row:first-of-type { border-radius: var(--radius-md) var(--radius-md) 0 0; }
  .setting-row:last-of-type { border-radius: 0 0 var(--radius-md) var(--radius-md); margin-bottom: 0; }
  .setting-row:only-of-type { border-radius: var(--radius-md); }

  .setting-info {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }
  .setting-info label {
    font-size: 0.9rem;
    font-weight: 500;
    color: var(--color-text-primary);
    cursor: default;
  }
  .setting-hint {
    font-size: 0.75rem;
    color: var(--color-text-secondary);
  }

  select {
    appearance: none;
    background: var(--color-bg-primary);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-sm);
    padding: var(--spacing-xs) var(--spacing-md) var(--spacing-xs) var(--spacing-sm);
    font-size: 0.85rem;
    color: var(--color-text-primary);
    cursor: pointer;
    min-width: 120px;
    font-family: inherit;
  }
  select:focus {
    outline: none;
    border-color: var(--color-accent);
    box-shadow: 0 0 0 2px rgba(0, 122, 255, 0.2);
  }

  input[type="number"] {
    background: var(--color-bg-primary);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-sm);
    padding: var(--spacing-xs) var(--spacing-sm);
    font-size: 0.85rem;
    color: var(--color-text-primary);
    width: 100px;
    text-align: right;
    font-family: inherit;
  }
  input[type="number"]:focus {
    outline: none;
    border-color: var(--color-accent);
    box-shadow: 0 0 0 2px rgba(0, 122, 255, 0.2);
  }

  .range-control {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
    min-width: 180px;
  }
  .range-control input[type="range"] {
    flex: 1;
    accent-color: var(--color-accent);
  }
  .range-control span {
    width: 44px;
    text-align: right;
    font-size: 0.75rem;
    color: var(--color-text-secondary);
  }

  /* macOS-style toggle switch */
  .toggle {
    position: relative;
    display: inline-block;
    width: 40px;
    height: 24px;
    cursor: pointer;
  }
  .toggle input {
    opacity: 0;
    width: 0;
    height: 0;
    position: absolute;
  }
  .toggle-slider {
    position: absolute;
    inset: 0;
    background: var(--color-border);
    border-radius: 12px;
    transition: background-color 0.2s ease;
  }
  .toggle-slider::before {
    content: "";
    position: absolute;
    height: 20px;
    width: 20px;
    left: 2px;
    bottom: 2px;
    background: white;
    border-radius: 50%;
    transition: transform 0.2s ease;
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.2);
  }
  .toggle input:checked + .toggle-slider {
    background: var(--color-accent);
  }
  .toggle input:checked + .toggle-slider::before {
    transform: translateX(16px);
  }
  .toggle input:focus-visible + .toggle-slider {
    box-shadow: 0 0 0 2px rgba(0, 122, 255, 0.3);
  }

  .about-card {
    padding: var(--spacing-md);
    background: var(--color-bg-secondary);
    border-radius: var(--radius-md);
  }
  .app-name {
    font-size: 1rem;
    font-weight: 600;
    color: var(--color-text-primary);
    margin: 0 0 var(--spacing-xs) 0;
  }
  .version {
    font-weight: 400;
    color: var(--color-text-secondary);
    font-size: 0.85rem;
  }
  .about-description {
    font-size: 0.85rem;
    color: var(--color-text-secondary);
    line-height: 1.5;
    margin: 0;
  }
</style>
