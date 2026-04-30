<script lang="ts">
  import {
    dumpOnboardBlob,
    fetchCydiaBlobs,
    listSavedBlobs,
    saveShshBlob,
    type CydiaBlobAttempt,
    type SavedBlob,
  } from '$lib/api/shsh';
  import { deviceStore } from '$lib/stores/deviceStore.svelte';
  import { logStore } from '$lib/stores/logStore.svelte';

  type Tab = 'save' | 'cydia' | 'onboard' | 'library';

  let activeTab = $state<Tab>('save');

  let device = $derived(deviceStore.state);

  let savedDir = $state('');
  let saveDeviceType = $state('');
  let saveEcid = $state('');
  let saveBoard = $state('');
  let saveVersion = $state('');
  let saveBuild = $state('');
  let saveManifest = $state('');
  let saveApnonce = $state('');
  let saveGenerator = $state('0x1111111111111111');

  let cydiaBuilds = $state('');
  let cydiaResults = $state<CydiaBlobAttempt[]>([]);

  let dumpRawPath = $state('');
  let dumpOutputPath = $state('');

  let blobs = $state<SavedBlob[]>([]);
  let isWorking = $state(false);
  let errorMessage = $state<string | null>(null);

  $effect(() => {
    if (device.product_type && !saveDeviceType) saveDeviceType = device.product_type;
    if (device.ecid && !saveEcid) saveEcid = device.ecid;
    if (device.ios_version && !saveVersion) saveVersion = device.ios_version;
  });

  async function withWorking<T>(label: string, fn: () => Promise<T>): Promise<T | null> {
    isWorking = true;
    errorMessage = null;
    logStore.append(`${label}...`, 'info');
    try {
      const result = await fn();
      logStore.append(`${label} ok`, 'info');
      return result;
    } catch (error) {
      errorMessage = error instanceof Error ? error.message : String(error);
      logStore.append(`${label} failed: ${errorMessage}`, 'stderr');
      return null;
    } finally {
      isWorking = false;
    }
  }

  function nullable(value: string): string | null {
    const trimmed = value.trim();
    return trimmed === '' ? null : trimmed;
  }

  async function handleSave() {
    if (!savedDir.trim()) {
      errorMessage = 'Output directory is required.';
      return;
    }
    const result = await withWorking('Save SHSH (tsschecker)', () =>
      saveShshBlob({
        deviceType: saveDeviceType.trim(),
        deviceEcid: saveEcid.trim(),
        boardConfig: nullable(saveBoard),
        iosVersion: saveVersion.trim(),
        buildId: nullable(saveBuild),
        buildManifestPath: nullable(saveManifest),
        apnonce: nullable(saveApnonce),
        generator: nullable(saveGenerator),
        outputDir: savedDir.trim(),
      }),
    );
    if (result) {
      logStore.append(`Saved: ${result.blobPaths.join(', ')}`, 'info');
      await refreshLibrary();
    }
  }

  async function handleCydia() {
    if (!savedDir.trim()) {
      errorMessage = 'Output directory is required.';
      return;
    }
    const buildIds = cydiaBuilds.split(/[\s,]+/).map((b) => b.trim()).filter(Boolean);
    if (buildIds.length === 0) {
      errorMessage = 'Provide at least one build ID (space- or comma-separated).';
      return;
    }
    const result = await withWorking('Fetch Cydia blobs', () =>
      fetchCydiaBlobs({
        deviceType: saveDeviceType.trim(),
        deviceEcid: saveEcid.trim(),
        buildIds,
        outputDir: savedDir.trim(),
      }),
    );
    if (result) {
      cydiaResults = result.attempts;
      const savedCount = result.attempts.filter((a) => a.saved).length;
      logStore.append(
        `Cydia: ${savedCount}/${result.attempts.length} blob(s) saved`,
        savedCount === 0 ? 'stderr' : 'info',
      );
      await refreshLibrary();
    }
  }

  async function handleDump() {
    const result = await withWorking('Convert raw dump to SHSH', () =>
      dumpOnboardBlob({
        rawDumpPath: dumpRawPath.trim(),
        outputPath: dumpOutputPath.trim(),
      }),
    );
    if (result) {
      logStore.append(`Onboard blob saved to ${result.blobPath}`, 'info');
      await refreshLibrary();
    }
  }

  async function refreshLibrary() {
    if (!savedDir.trim()) {
      blobs = [];
      return;
    }
    const result = await withWorking('List saved blobs', () =>
      listSavedBlobs({ directory: savedDir.trim() }),
    );
    if (result) {
      blobs = result.blobs;
    }
  }

  function formatSize(bytes: number): string {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
  }

  function formatDate(unix: number | null): string {
    if (unix === null) return '—';
    return new Date(unix * 1000).toLocaleString();
  }
</script>

<div class="view">
  <div class="view-header">
    <div>
      <h1>SHSH Blobs</h1>
      <p>Save, fetch, dump, and organize signing tickets used for downgrades and tethered restores.</p>
    </div>
  </div>

  <section class="device-summary">
    <div>
      <span class="label">Device</span>
      <strong>{device.product_type ?? 'Not detected'}</strong>
    </div>
    <div>
      <span class="label">ECID</span>
      <strong>{device.ecid ?? 'Unknown'}</strong>
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
    <label class="field">
      <span>Saved blobs directory</span>
      <input
        bind:value={savedDir}
        placeholder="/Users/you/.legacykit/saved/shsh"
        onblur={refreshLibrary}
      />
    </label>
    <p class="panel-note">
      All commands write to this directory. The library tab lists everything LegacyKit can
      find here.
    </p>
  </section>

  <div class="tabs" role="tablist">
    <button class:active={activeTab === 'save'} onclick={() => (activeTab = 'save')}>tsschecker</button>
    <button class:active={activeTab === 'cydia'} onclick={() => (activeTab = 'cydia')}>Cydia servers</button>
    <button class:active={activeTab === 'onboard'} onclick={() => (activeTab = 'onboard')}>Onboard dump</button>
    <button class:active={activeTab === 'library'} onclick={() => { activeTab = 'library'; refreshLibrary(); }}>Library</button>
  </div>

  {#if activeTab === 'save'}
    <section class="panel">
      <div class="section-title"><span>1</span><h2>Save blobs with tsschecker</h2></div>
      <p class="panel-note">
        Apple still signs whatever firmware appears on its TSS server. Run while the version is signed
        to capture a blob you can use later with futurerestore.
      </p>

      <div class="grid">
        <label class="field">
          <span>Device type</span>
          <input bind:value={saveDeviceType} placeholder="iPhone6,2" />
        </label>
        <label class="field">
          <span>ECID</span>
          <input bind:value={saveEcid} placeholder="0x123ABC..." />
        </label>
        <label class="field">
          <span>iOS version</span>
          <input bind:value={saveVersion} placeholder="10.3.3" />
        </label>
        <label class="field">
          <span>Build ID (optional)</span>
          <input bind:value={saveBuild} placeholder="14G60" />
        </label>
        <label class="field">
          <span>Board config (optional)</span>
          <input bind:value={saveBoard} placeholder="n53ap" />
        </label>
        <label class="field">
          <span>BuildManifest.plist (optional)</span>
          <input bind:value={saveManifest} placeholder="/path/to/BuildManifest.plist" />
        </label>
        <label class="field">
          <span>APNonce (optional)</span>
          <input bind:value={saveApnonce} placeholder="hex (overrides generator)" />
        </label>
        <label class="field">
          <span>Generator</span>
          <input bind:value={saveGenerator} placeholder="0x1111111111111111" />
        </label>
      </div>

      <div class="actions">
        <button class="primary" onclick={handleSave} disabled={isWorking}>
          {isWorking ? 'Working…' : 'Save blob'}
        </button>
      </div>
    </section>
  {:else if activeTab === 'cydia'}
    <section class="panel">
      <div class="section-title"><span>2</span><h2>Cydia / saurik server blobs</h2></div>
      <p class="panel-note">
        Tries each build ID against <code>cydia.saurik.com</code>. Only a handful of older firmwares
        are mirrored, so most attempts will report "Not saved" — that's expected.
      </p>

      <div class="grid">
        <label class="field">
          <span>Device type</span>
          <input bind:value={saveDeviceType} placeholder="iPhone6,2" />
        </label>
        <label class="field">
          <span>ECID</span>
          <input bind:value={saveEcid} placeholder="0x123ABC..." />
        </label>
      </div>

      <label class="field">
        <span>Build IDs (space- or comma-separated)</span>
        <input bind:value={cydiaBuilds} placeholder="11D257 11G79 12B440" />
      </label>

      <div class="actions">
        <button class="primary" onclick={handleCydia} disabled={isWorking}>
          {isWorking ? 'Working…' : 'Try Cydia'}
        </button>
      </div>

      {#if cydiaResults.length > 0}
        <table class="results">
          <thead>
            <tr><th>Build</th><th>Status</th><th>Path / message</th></tr>
          </thead>
          <tbody>
            {#each cydiaResults as attempt}
              <tr>
                <td><code>{attempt.buildId}</code></td>
                <td class={attempt.saved ? 'good' : 'muted'}>
                  {attempt.saved ? 'Saved' : 'Not saved'}
                </td>
                <td><code class="wrap">{attempt.blobPath ?? attempt.message ?? ''}</code></td>
              </tr>
            {/each}
          </tbody>
        </table>
      {/if}
    </section>
  {:else if activeTab === 'onboard'}
    <section class="panel">
      <div class="section-title"><span>3</span><h2>Convert raw onboard dump → SHSH</h2></div>
      <p class="panel-note">
        For 64-bit devices, dump <code>/dev/rdisk1</code> over SSH (see SSH Ramdisk view) into a raw file,
        then point this tool at the raw dump to get a usable .shsh2.
      </p>

      <label class="field">
        <span>Raw dump path</span>
        <input bind:value={dumpRawPath} placeholder="/path/to/dump.raw" />
      </label>
      <label class="field">
        <span>Output blob path</span>
        <input
          bind:value={dumpOutputPath}
          placeholder="/path/to/saved/shsh/<ecid>-<device>-<date>.shsh2"
        />
      </label>

      <div class="actions">
        <button class="primary" onclick={handleDump} disabled={isWorking}>
          {isWorking ? 'Working…' : 'Convert with img4tool'}
        </button>
      </div>
    </section>
  {:else if activeTab === 'library'}
    <section class="panel">
      <div class="section-title"><span>4</span><h2>Saved blob library</h2></div>
      <p class="panel-note">
        Lists every <code>.shsh</code> / <code>.shsh2</code> in the directory above. File names following
        tsschecker's <code>ECID_DEVICE_BOARD_VERSION-BUILD_NONCE</code> convention are parsed automatically.
      </p>
      <div class="actions">
        <button class="secondary" onclick={refreshLibrary} disabled={isWorking}>
          Refresh
        </button>
      </div>
      {#if blobs.length === 0}
        <div class="empty">No blobs found. Save one first or check the directory path.</div>
      {:else}
        <table class="results">
          <thead>
            <tr>
              <th>Device</th><th>iOS</th><th>Build</th><th>ECID</th>
              <th>Size</th><th>Modified</th><th>File</th>
            </tr>
          </thead>
          <tbody>
            {#each blobs as blob}
              <tr>
                <td>{blob.deviceType ?? '—'}</td>
                <td>{blob.iosVersion ?? '—'}</td>
                <td>{blob.buildId ?? '—'}</td>
                <td><code>{blob.deviceEcid ?? '—'}</code></td>
                <td>{formatSize(blob.sizeBytes)}</td>
                <td>{formatDate(blob.modifiedUnix)}</td>
                <td><code class="wrap" title={blob.path}>{blob.fileName}</code></td>
              </tr>
            {/each}
          </tbody>
        </table>
      {/if}
    </section>
  {/if}
</div>

<style>
  .view {
    padding: var(--spacing-xl);
    max-width: 1024px;
  }

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

  .grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: var(--spacing-sm);
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

  .actions {
    display: flex;
    gap: var(--spacing-sm);
    justify-content: flex-end;
  }

  button.primary {
    background: var(--color-accent);
    border: 1px solid var(--color-accent);
    border-radius: var(--radius-sm);
    color: white;
    font-size: 0.85rem;
    font-weight: 600;
    padding: 8px 12px;
  }
  button.secondary {
    background: var(--color-bg-primary);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-sm);
    color: var(--color-text-primary);
    font-size: 0.85rem;
    font-weight: 600;
    padding: 8px 12px;
  }
  button:disabled {
    cursor: not-allowed;
    opacity: 0.5;
  }

  .results {
    width: 100%;
    border-collapse: collapse;
    margin-top: var(--spacing-md);
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
  .results td.good { color: var(--color-success, #2ea043); font-weight: 600; }
  .results td.muted { color: var(--color-text-secondary); }
  .wrap {
    word-break: break-all;
    font-size: 0.75rem;
  }

  .empty {
    padding: var(--spacing-md);
    border: 1px dashed var(--color-border);
    border-radius: var(--radius-sm);
    color: var(--color-text-secondary);
    text-align: center;
    font-size: 0.85rem;
  }

  code {
    font-family: var(--font-mono, ui-monospace, SFMono-Regular, monospace);
    font-size: 0.78rem;
  }
</style>
