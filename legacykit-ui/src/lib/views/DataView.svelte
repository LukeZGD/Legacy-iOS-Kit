<script lang="ts">
  import {
    createBackup,
    eraseDevice,
    listBackups,
    restoreBackup,
    setBackupEncryption,
    ERASE_CONFIRMATION,
    type BackupEncryptionAction,
    type BackupEntry,
  } from '$lib/api/data';
  import { deviceStore } from '$lib/stores/deviceStore.svelte';
  import { logStore } from '$lib/stores/logStore.svelte';

  type Tab = 'backup' | 'restore' | 'encryption' | 'erase';

  let activeTab = $state<Tab>('backup');
  let backupRoot = $state('');
  let isWorking = $state(false);
  let errorMessage = $state<string | null>(null);

  let device = $derived(deviceStore.state);
  let udid = $derived(device.udid ?? '');

  let backupFull = $state(true);
  let backups = $state<BackupEntry[]>([]);

  let selectedBackup = $state('');
  let restoreSystem = $state(true);
  let restoreSettings = $state(true);
  let restoreReboot = $state(false);

  let eraseConfirmation = $state('');

  async function withWorking<T>(label: string, fn: () => Promise<T>): Promise<T | null> {
    isWorking = true;
    errorMessage = null;
    logStore.append(`${label}...`, 'info');
    try {
      const result = await fn();
      logStore.append(`${label} ok`, 'info');
      return result;
    } catch (err) {
      errorMessage = err instanceof Error ? err.message : String(err);
      logStore.append(`${label} failed: ${errorMessage}`, 'stderr');
      return null;
    } finally {
      isWorking = false;
    }
  }

  async function refreshBackups() {
    if (!backupRoot.trim()) {
      backups = [];
      return;
    }
    const result = await withWorking('List backups', () =>
      listBackups({ backupRoot: backupRoot.trim() }),
    );
    if (result) {
      backups = result.backups;
    }
  }

  async function handleBackup() {
    if (!backupRoot.trim()) {
      errorMessage = 'Backup root directory is required.';
      return;
    }
    const result = await withWorking('Create backup', () =>
      createBackup({
        backupRoot: backupRoot.trim(),
        udid: udid || null,
        full: backupFull,
      }),
    );
    if (result) {
      logStore.append(`Backup created at ${result.backupPath}`, 'info');
      await refreshBackups();
    }
  }

  async function handleRestore() {
    if (!selectedBackup.trim()) {
      errorMessage = 'Select a backup to restore.';
      return;
    }
    const result = await withWorking('Restore backup', () =>
      restoreBackup({
        backupPath: selectedBackup,
        udid: udid || null,
        system: restoreSystem,
        settings: restoreSettings,
        reboot: restoreReboot,
      }),
    );
    if (result) {
      logStore.append(`Restored from ${result.backupPath}`, 'info');
    }
  }

  async function handleEncryption(action: BackupEncryptionAction) {
    const label =
      action === 'on' ? 'Enable backup encryption'
      : action === 'off' ? 'Disable backup encryption'
      : 'Change backup password';
    await withWorking(label, () => setBackupEncryption({ action, udid: udid || null }));
  }

  async function handleErase() {
    if (eraseConfirmation !== ERASE_CONFIRMATION) {
      errorMessage = `Type the exact phrase to confirm: ${ERASE_CONFIRMATION}`;
      return;
    }
    const ok = confirm(
      'This will erase ALL content and settings on the device. This cannot be undone. Continue?',
    );
    if (!ok) return;
    const result = await withWorking('Erase device', () =>
      eraseDevice({ udid: udid || null, confirmation: eraseConfirmation }),
    );
    if (result) {
      logStore.append('Erase request issued', 'info');
      eraseConfirmation = '';
    }
  }

  function formatSize(bytes: number): string {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
    return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
  }

  function formatDate(unix: number | null): string {
    if (unix === null) return '—';
    return new Date(unix * 1000).toLocaleString();
  }
</script>

<div class="view">
  <div class="view-header">
    <div>
      <h1>Data Management</h1>
      <p>Back up, restore, and erase the device via <code>idevicebackup2</code>.</p>
    </div>
  </div>

  <section class="device-summary">
    <div>
      <span class="label">Device</span>
      <strong>{device.product_type ?? 'Not detected'}</strong>
    </div>
    <div>
      <span class="label">UDID</span>
      <strong title={device.udid ?? ''}>{device.udid ? `${device.udid.slice(0, 12)}…` : 'Unknown'}</strong>
    </div>
    <div>
      <span class="label">Mode</span>
      <strong>{device.mode}</strong>
    </div>
  </section>

  {#if errorMessage}
    <div class="error-state">{errorMessage}</div>
  {/if}

  <section class="panel">
    <label class="field">
      <span>Backup root directory</span>
      <input
        bind:value={backupRoot}
        placeholder="/Users/you/.legacykit/saved/backups"
        onblur={refreshBackups}
      />
    </label>
    <p class="panel-note">
      Backups are stored as timestamped subdirectories under this root. Restore reads from any
      subdirectory you select below.
    </p>
  </section>

  <div class="tabs" role="tablist">
    <button class:active={activeTab === 'backup'} onclick={() => (activeTab = 'backup')}>Backup</button>
    <button class:active={activeTab === 'restore'} onclick={() => { activeTab = 'restore'; refreshBackups(); }}>Restore</button>
    <button class:active={activeTab === 'encryption'} onclick={() => (activeTab = 'encryption')}>Encryption</button>
    <button class:active={activeTab === 'erase'} onclick={() => (activeTab = 'erase')}>Erase</button>
  </div>

  {#if activeTab === 'backup'}
    <section class="panel">
      <div class="section-title"><span>1</span><h2>Create backup</h2></div>
      <p class="panel-note">
        Runs <code>idevicebackup2 backup</code> against the connected device. Full backups capture
        everything; incremental skips unchanged files when a previous backup exists in the same root.
      </p>
      <label class="checkbox">
        <input type="checkbox" bind:checked={backupFull} />
        <span>Full backup (<code>--full</code>)</span>
      </label>
      <div class="actions">
        <button class="primary" onclick={handleBackup} disabled={isWorking}>
          {isWorking ? 'Working…' : 'Start backup'}
        </button>
      </div>
    </section>
  {:else if activeTab === 'restore'}
    <section class="panel">
      <div class="section-title"><span>2</span><h2>Restore backup</h2></div>
      <p class="panel-note">
        Restoring overwrites data on the device. Pick a backup, choose flags, and confirm. The
        device will reboot after a successful restore if <code>--reboot</code> is set.
      </p>

      <div class="actions" style="margin-bottom: var(--spacing-md);">
        <button class="secondary" onclick={refreshBackups} disabled={isWorking}>
          Refresh list
        </button>
      </div>

      {#if backups.length === 0}
        <div class="empty">
          No backups in this directory yet. Create one from the Backup tab.
        </div>
      {:else}
        <table class="results">
          <thead>
            <tr><th></th><th>Name</th><th>Size</th><th>Modified</th></tr>
          </thead>
          <tbody>
            {#each backups as b}
              <tr>
                <td>
                  <input
                    type="radio"
                    name="backup-select"
                    value={b.path}
                    bind:group={selectedBackup}
                  />
                </td>
                <td><code>{b.name}</code></td>
                <td>{formatSize(b.sizeBytes)}</td>
                <td>{formatDate(b.modifiedUnix)}</td>
              </tr>
            {/each}
          </tbody>
        </table>
      {/if}

      <div class="checkbox-row">
        <label class="checkbox">
          <input type="checkbox" bind:checked={restoreSystem} />
          <span><code>--system</code></span>
        </label>
        <label class="checkbox">
          <input type="checkbox" bind:checked={restoreSettings} />
          <span><code>--settings</code></span>
        </label>
        <label class="checkbox">
          <input type="checkbox" bind:checked={restoreReboot} />
          <span><code>--reboot</code></span>
        </label>
      </div>

      <div class="actions">
        <button
          class="primary"
          onclick={handleRestore}
          disabled={isWorking || !selectedBackup}
        >
          {isWorking ? 'Working…' : 'Restore'}
        </button>
      </div>
    </section>
  {:else if activeTab === 'encryption'}
    <section class="panel">
      <div class="section-title"><span>3</span><h2>Backup encryption</h2></div>
      <p class="panel-note">
        Toggles backup encryption flag on the device or runs the password change flow. Both prompt
        on the device for the existing/new password.
      </p>
      <div class="actions">
        <button class="secondary" onclick={() => handleEncryption('on')} disabled={isWorking}>
          Enable encryption
        </button>
        <button class="secondary" onclick={() => handleEncryption('off')} disabled={isWorking}>
          Disable encryption
        </button>
        <button class="secondary" onclick={() => handleEncryption('changePassword')} disabled={isWorking}>
          Change password
        </button>
      </div>
    </section>
  {:else if activeTab === 'erase'}
    <section class="panel danger-panel">
      <div class="section-title"><span>!</span><h2>Erase All Content and Settings</h2></div>
      <p class="panel-note">
        This issues an <code>idevicebackup2 erase</code> command and the device returns to the
        setup screen. Everything on the device is permanently destroyed. Type the confirmation
        phrase exactly to enable the button.
      </p>
      <p class="confirmation-hint">
        Required phrase: <code>{ERASE_CONFIRMATION}</code>
      </p>
      <label class="field">
        <span>Confirmation</span>
        <input bind:value={eraseConfirmation} placeholder="Type the phrase exactly" />
      </label>
      <div class="actions">
        <button
          class="danger"
          onclick={handleErase}
          disabled={isWorking || eraseConfirmation !== ERASE_CONFIRMATION}
        >
          {isWorking ? 'Working…' : 'Erase device'}
        </button>
      </div>
    </section>
  {/if}

  <p class="footer-note">
    Filesystem mount via sshfs is omitted from this view — sshfs requires a userspace driver and a
    jailbroken device, and lives more naturally next to the SSH ramdisk flow.
  </p>
</div>

<style>
  .view { padding: var(--spacing-xl); max-width: 1024px; }
  .view-header { margin-bottom: var(--spacing-lg); }
  .view-header h1 {
    color: var(--color-text-primary);
    font-size: 1.5rem;
    font-weight: 700;
    margin: 0 0 var(--spacing-xs);
  }
  .view-header p {
    color: var(--color-text-secondary);
    font-size: 0.9rem;
    line-height: 1.5;
    margin: 0;
  }

  .device-summary {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 1px;
    overflow: hidden;
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    background: var(--color-border);
    margin-bottom: var(--spacing-lg);
  }
  .device-summary div {
    display: flex;
    flex-direction: column;
    gap: 2px;
    background: var(--color-bg-secondary);
    padding: var(--spacing-md);
  }
  .label {
    color: var(--color-text-secondary);
    font-size: 0.75rem;
  }
  .device-summary strong {
    color: var(--color-text-primary);
    font-size: 0.95rem;
  }

  .panel {
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    background: var(--color-bg-secondary);
    padding: var(--spacing-md);
    margin-bottom: var(--spacing-md);
  }
  .panel.danger-panel {
    border-color: color-mix(in srgb, var(--color-danger) 45%, var(--color-border));
  }
  .panel.danger-panel .section-title span {
    background: var(--color-danger);
  }

  .section-title {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
    margin-bottom: var(--spacing-md);
  }
  .section-title span {
    display: inline-grid;
    place-items: center;
    width: 22px;
    height: 22px;
    border-radius: 50%;
    background: var(--color-accent);
    color: white;
    font-size: 0.75rem;
    font-weight: 700;
  }
  .section-title h2 {
    color: var(--color-text-primary);
    font-size: 1rem;
    margin: 0;
  }

  .panel-note {
    color: var(--color-text-secondary);
    font-size: 0.8rem;
    line-height: 1.5;
    margin: 0 0 var(--spacing-md);
  }
  .footer-note {
    color: var(--color-text-secondary);
    font-size: 0.78rem;
    text-align: center;
    margin-top: var(--spacing-md);
  }

  .error-state {
    border: 1px solid color-mix(in srgb, var(--color-danger) 45%, var(--color-border));
    border-radius: var(--radius-md);
    background: var(--color-bg-secondary);
    color: var(--color-danger);
    font-size: 0.875rem;
    padding: var(--spacing-md);
    margin-bottom: var(--spacing-md);
  }

  .tabs {
    display: flex;
    gap: var(--spacing-xs);
    margin-bottom: var(--spacing-md);
    border-bottom: 1px solid var(--color-border);
  }
  .tabs button {
    background: transparent;
    border: none;
    padding: 8px 14px;
    font-size: 0.85rem;
    font-weight: 600;
    color: var(--color-text-secondary);
    border-bottom: 2px solid transparent;
    cursor: pointer;
  }
  .tabs button.active {
    color: var(--color-text-primary);
    border-bottom-color: var(--color-accent);
  }

  .field {
    display: flex;
    flex-direction: column;
    gap: 4px;
    color: var(--color-text-secondary);
    font-size: 0.75rem;
    font-weight: 600;
  }
  .field input {
    width: 100%;
    border: 1px solid var(--color-border);
    border-radius: var(--radius-sm);
    background: var(--color-bg-primary);
    color: var(--color-text-primary);
    font: inherit;
    font-size: 0.85rem;
    padding: 8px 10px;
  }

  .checkbox {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    color: var(--color-text-primary);
    font-size: 0.85rem;
  }
  .checkbox-row {
    display: flex;
    gap: var(--spacing-md);
    margin: var(--spacing-md) 0;
    flex-wrap: wrap;
  }

  .actions {
    display: flex;
    gap: var(--spacing-sm);
    justify-content: flex-end;
  }

  button.primary, button.secondary, button.danger {
    border-radius: var(--radius-sm);
    font-size: 0.85rem;
    font-weight: 600;
    padding: 8px 12px;
  }
  button.primary {
    background: var(--color-accent);
    border: 1px solid var(--color-accent);
    color: white;
  }
  button.secondary {
    background: var(--color-bg-primary);
    border: 1px solid var(--color-border);
    color: var(--color-text-primary);
  }
  button.danger {
    background: var(--color-danger);
    border: 1px solid var(--color-danger);
    color: white;
  }
  button:disabled {
    cursor: not-allowed;
    opacity: 0.5;
  }

  .results {
    width: 100%;
    border-collapse: collapse;
    font-size: 0.8rem;
  }
  .results th, .results td {
    text-align: left;
    padding: 6px 8px;
    border-bottom: 1px solid var(--color-border);
    color: var(--color-text-primary);
  }
  .results th {
    font-weight: 600;
    color: var(--color-text-secondary);
    font-size: 0.7rem;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .empty {
    padding: var(--spacing-md);
    border: 1px dashed var(--color-border);
    border-radius: var(--radius-sm);
    color: var(--color-text-secondary);
    text-align: center;
    font-size: 0.85rem;
    margin-bottom: var(--spacing-md);
  }

  .confirmation-hint {
    color: var(--color-text-secondary);
    font-size: 0.8rem;
    margin: 0 0 var(--spacing-sm);
  }

  code { font-family: var(--font-mono, ui-monospace, SFMono-Regular, monospace); font-size: 0.78rem; }
</style>
