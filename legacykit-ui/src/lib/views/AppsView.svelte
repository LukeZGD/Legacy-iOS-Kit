<script lang="ts">
  import {
    installIpa,
    listInstalledApps,
    uninstallApp,
    type AppListScope,
    type InstalledApp,
  } from '$lib/api/apps';
  import { deviceStore } from '$lib/stores/deviceStore.svelte';
  import { logStore } from '$lib/stores/logStore.svelte';

  let scope = $state<AppListScope>('user');
  let apps = $state<InstalledApp[]>([]);
  let filter = $state('');
  let ipaPathsRaw = $state('');
  let isWorking = $state(false);
  let errorMessage = $state<string | null>(null);

  let device = $derived(deviceStore.state);
  let filteredApps = $derived(
    filter.trim() === ''
      ? apps
      : apps.filter((a) => {
          const q = filter.toLowerCase();
          return (
            a.bundleId.toLowerCase().includes(q) ||
            (a.displayName ?? '').toLowerCase().includes(q)
          );
        }),
  );

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

  async function refresh() {
    const result = await withWorking(`List ${scope} apps`, () =>
      listInstalledApps({ scope }),
    );
    if (result) {
      apps = result.apps;
    }
  }

  async function handleInstall() {
    const ipaPaths = ipaPathsRaw
      .split(/\r?\n/)
      .map((s) => s.trim())
      .filter(Boolean);
    if (ipaPaths.length === 0) {
      errorMessage = 'Provide at least one IPA path (one per line).';
      return;
    }
    const result = await withWorking(`Install ${ipaPaths.length} IPA(s)`, () =>
      installIpa({ ipaPaths }),
    );
    if (result) {
      logStore.append(`Installed: ${result.installed.join(', ')}`, 'info');
      ipaPathsRaw = '';
      await refresh();
    }
  }

  async function handleUninstall(bundleId: string) {
    const ok = confirm(`Uninstall ${bundleId}? This cannot be undone.`);
    if (!ok) return;
    const result = await withWorking(`Uninstall ${bundleId}`, () =>
      uninstallApp({ bundleId }),
    );
    if (result) {
      apps = apps.filter((a) => a.bundleId !== bundleId);
    }
  }
</script>

<div class="view">
  <div class="view-header">
    <div>
      <h1>App Management</h1>
      <p>List, sideload, and uninstall applications via <code>ideviceinstaller</code>.</p>
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
      <span class="label">iOS</span>
      <strong>{device.ios_version ?? 'Unknown'}</strong>
    </div>
  </section>

  {#if errorMessage}
    <div class="error-state">{errorMessage}</div>
  {/if}

  <section class="panel">
    <div class="section-title"><span>1</span><h2>Install IPA(s)</h2></div>
    <p class="panel-note">
      One absolute path per line. For unsigned IPAs the device needs AppSync (jailbroken).
      Signed builds (TrollStore-compatible, sideloaded with a developer cert) work without it.
    </p>
    <label class="field">
      <span>IPA paths</span>
      <textarea
        rows="4"
        bind:value={ipaPathsRaw}
        placeholder={'/Users/you/Apps/Foo.ipa\n/Users/you/Apps/Bar.ipa'}
      ></textarea>
    </label>
    <div class="actions">
      <button class="primary" onclick={handleInstall} disabled={isWorking}>
        {isWorking ? 'Working…' : 'Install'}
      </button>
    </div>
  </section>

  <section class="panel">
    <div class="section-title"><span>2</span><h2>Installed apps</h2></div>

    <div class="row">
      <label class="field inline">
        <span>Scope</span>
        <select bind:value={scope}>
          <option value="user">User</option>
          <option value="system">System</option>
          <option value="all">All</option>
        </select>
      </label>
      <label class="field inline grow">
        <span>Filter</span>
        <input bind:value={filter} placeholder="bundle id or display name" />
      </label>
      <div class="actions">
        <button class="secondary" onclick={refresh} disabled={isWorking}>
          {isWorking ? 'Working…' : 'Refresh'}
        </button>
      </div>
    </div>

    {#if filteredApps.length === 0}
      <div class="empty">
        {apps.length === 0
          ? 'No apps loaded yet. Click Refresh to query the device.'
          : 'No apps match the current filter.'}
      </div>
    {:else}
      <table class="results">
        <thead>
          <tr>
            <th>Display name</th><th>Bundle ID</th><th>Version</th><th></th>
          </tr>
        </thead>
        <tbody>
          {#each filteredApps as app}
            <tr>
              <td>{app.displayName ?? '—'}</td>
              <td><code class="wrap">{app.bundleId}</code></td>
              <td>{app.version ?? '—'}</td>
              <td class="row-actions">
                <button
                  class="danger"
                  onclick={() => handleUninstall(app.bundleId)}
                  disabled={isWorking}
                >
                  Uninstall
                </button>
              </td>
            </tr>
          {/each}
        </tbody>
      </table>
    {/if}
  </section>

  <p class="footer-note">
    App dumping (Clutch / ipainstaller) requires an SSH ramdisk session — that flow will live alongside
    the SSH ramdisk view in a follow-up phase.
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

  .field {
    display: flex;
    flex-direction: column;
    gap: 4px;
    color: var(--color-text-secondary);
    font-size: 0.75rem;
    font-weight: 600;
  }
  .field input, .field select, .field textarea {
    width: 100%;
    border: 1px solid var(--color-border);
    border-radius: var(--radius-sm);
    background: var(--color-bg-primary);
    color: var(--color-text-primary);
    font: inherit;
    font-size: 0.85rem;
    padding: 8px 10px;
  }
  .field textarea {
    font-family: var(--font-mono, ui-monospace, SFMono-Regular, monospace);
    font-size: 0.78rem;
    resize: vertical;
  }
  .field.inline { flex-direction: column; }
  .field.grow { flex: 1; }

  .row {
    display: flex;
    gap: var(--spacing-sm);
    align-items: end;
    margin-bottom: var(--spacing-md);
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
    background: var(--color-bg-primary);
    border: 1px solid color-mix(in srgb, var(--color-danger) 45%, var(--color-border));
    color: var(--color-danger);
  }
  button:disabled {
    cursor: not-allowed;
    opacity: 0.5;
  }

  .results {
    width: 100%;
    border-collapse: collapse;
    margin-top: var(--spacing-sm);
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
  .row-actions { text-align: right; }
  .wrap { word-break: break-all; font-size: 0.75rem; }

  .empty {
    padding: var(--spacing-md);
    border: 1px dashed var(--color-border);
    border-radius: var(--radius-sm);
    color: var(--color-text-secondary);
    text-align: center;
    font-size: 0.85rem;
  }

  code { font-family: var(--font-mono, ui-monospace, SFMono-Regular, monospace); font-size: 0.78rem; }
</style>
