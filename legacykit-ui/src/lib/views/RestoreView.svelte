<script lang="ts">
  import {
    downloadIpsw,
    getRestoreOptions,
    prepareIpsw,
    previewRestoreCommand,
    startRestore,
    verifyIpsw,
    type IpswPrepareResult,
    type IpswVerifyResult,
    type RestoreCommandPreview,
    type RestoreOption,
    type RestoreOptionsResponse,
    type RestoreRunRequest,
    type RestoreTool,
  } from '$lib/api/restore';
  import { deviceStore } from '$lib/stores/deviceStore.svelte';
  import { logStore } from '$lib/stores/logStore.svelte';

  let restoreOptions = $state<RestoreOptionsResponse | null>(null);
  let selectedIndex = $state(0);
  let isLoadingOptions = $state(false);
  let isWorking = $state(false);
  let errorMessage = $state<string | null>(null);
  let requestId = 0;

  let ipswPath = $state('');
  let downloadUrl = $state('');
  let downloadDir = $state('');
  let downloadFileName = $state('');
  let expectedSha1 = $state('');
  let verifyResult = $state<IpswVerifyResult | null>(null);

  let shshPath = $state('');
  let selectedTool = $state<RestoreTool>('ideviceRestore');
  let erase = $state(true);
  let update = $state(false);
  let usePwndfu = $state(false);
  let skipBlob = $state(false);
  let setNonce = $state(false);
  let noBaseband = $state(true);
  let latestSep = $state(false);
  let latestBaseband = $state(false);
  let preview = $state<RestoreCommandPreview | null>(null);

  let prepOutputDir = $state('');
  let isPreparing = $state(false);
  let prepResult = $state<IpswPrepareResult | null>(null);

  let selectedOption = $derived(restoreOptions?.options[selectedIndex] ?? null);
  let needsPrepStep = $derived(selectedOption?.kind === 'powdersnow');
  let effectiveIpswPath = $derived(prepResult?.outputPath || ipswPath);
  let commandRequest = $derived(buildCommandRequest());
  let canVerify = $derived(ipswPath.trim().endsWith('.ipsw') && !isWorking && !isPreparing);
  let canPrep = $derived(
    needsPrepStep && ipswPath.trim().endsWith('.ipsw') && prepOutputDir.trim() !== '' && !isWorking && !isPreparing
  );
  let canPreview = $derived(!!effectiveIpswPath.trim() && !isWorking && !isPreparing);
  let canRun = $derived(!!preview && !isWorking && !isPreparing);

  $effect(() => {
    const device = { ...deviceStore.state };
    void loadRestoreOptions(device);
  });

  $effect(() => {
    const option = selectedOption;
    if (!option) return;

    selectedTool = defaultToolForOption(option);
    setNonce = option.kind === 'setNonce';
    usePwndfu = option.kind === 'tethered';
    prepResult = null;
    preview = null;
  });

  async function loadRestoreOptions(device: typeof deviceStore.state) {
    const currentRequest = ++requestId;
    isLoadingOptions = true;
    errorMessage = null;

    try {
      const response = await getRestoreOptions(device);
      if (currentRequest === requestId) {
        restoreOptions = response;
        selectedIndex = 0;
      }
    } catch (error) {
      if (currentRequest === requestId) {
        errorMessage = error instanceof Error ? error.message : String(error);
        restoreOptions = null;
      }
    } finally {
      if (currentRequest === requestId) {
        isLoadingOptions = false;
      }
    }
  }

  function selectOption(index: number) {
    selectedIndex = index;
    verifyResult = null;
    preview = null;
  }

  async function handleDownload() {
    isWorking = true;
    errorMessage = null;
    preview = null;
    logStore.append('Starting IPSW download...', 'info');

    try {
      const result = await downloadIpsw({
        url: downloadUrl,
        outputDir: downloadDir,
        fileName: downloadFileName || null,
      });
      ipswPath = result.path;
      logStore.append(`Downloaded IPSW: ${result.path}`, 'info');
    } catch (error) {
      errorMessage = error instanceof Error ? error.message : String(error);
      logStore.append(`Download failed: ${errorMessage}`, 'stderr');
    } finally {
      isWorking = false;
    }
  }

  async function handleVerify() {
    isWorking = true;
    errorMessage = null;
    verifyResult = null;
    preview = null;

    try {
      verifyResult = await verifyIpsw({
        path: ipswPath,
        expectedSha1: expectedSha1 || null,
      });
      logStore.append(`IPSW SHA-1: ${verifyResult.calculatedSha1}`, 'info');
    } catch (error) {
      errorMessage = error instanceof Error ? error.message : String(error);
      logStore.append(`Verification failed: ${errorMessage}`, 'stderr');
    } finally {
      isWorking = false;
    }
  }

  async function handlePreview(dryRun = true) {
    isWorking = true;
    errorMessage = null;
    const request = { ...commandRequest, dryRun };

    try {
      preview = await previewRestoreCommand(request);
      logStore.append(`Restore command: ${preview.binary} ${preview.args.join(' ')}`, 'info');
    } catch (error) {
      errorMessage = error instanceof Error ? error.message : String(error);
      logStore.append(`Preview failed: ${errorMessage}`, 'stderr');
    } finally {
      isWorking = false;
    }
  }

  async function handleStartRestore() {
    isWorking = true;
    errorMessage = null;
    const request = { ...commandRequest, dryRun: false };

    try {
      preview = await startRestore(request);
    } catch (error) {
      errorMessage = error instanceof Error ? error.message : String(error);
      logStore.append(`Restore failed: ${errorMessage}`, 'stderr');
    } finally {
      isWorking = false;
    }
  }

  function buildCommandRequest(): RestoreRunRequest {
    return {
      tool: selectedTool,
      ipswPath: effectiveIpswPath,
      shshPath: shshPath || null,
      erase,
      update,
      usePwndfu,
      skipBlob,
      setNonce,
      noBaseband,
      latestSep,
      latestBaseband,
      dryRun: true,
    };
  }

  function defaultToolForOption(option: RestoreOption): RestoreTool {
    if (option.kind === 'blobRestore' || option.kind === 'setNonce' || option.kind === 'tethered') {
      return 'futureRestore';
    }
    return 'ideviceRestore';
  }

  async function handlePrepareIpsw() {
    isPreparing = true;
    prepResult = null;
    errorMessage = null;
    preview = null;
    const device = deviceStore.state;

    logStore.append('Preparing custom IPSW with powdersn0w...', 'info');
    try {
      prepResult = await prepareIpsw({
        ipswPath,
        outputDir: prepOutputDir,
        shshPath: selectedOption?.requiresBlobs ? (shshPath || null) : null,
        deviceEcid: device.ecid || null,
      });
      logStore.append(`Custom IPSW ready: ${prepResult.outputPath}`, 'info');
    } catch (error) {
      errorMessage = error instanceof Error ? error.message : String(error);
      logStore.append(`Preparation failed: ${errorMessage}`, 'stderr');
    } finally {
      isPreparing = false;
    }
  }
</script>

<div class="view">
  <div class="view-header">
    <div>
      <h1>Restore & Downgrade</h1>
      <p>Choose a path, prepare the IPSW, then preview the restore command.</p>
    </div>
  </div>

  {#if isLoadingOptions && !restoreOptions}
    <div class="empty-state">Loading restore options...</div>
  {:else if restoreOptions}
    <section class="device-summary">
      <div>
        <span class="label">Device</span>
        <strong>{restoreOptions.productType ?? 'Not detected'}</strong>
      </div>
      <div>
        <span class="label">Processor</span>
        <strong>{restoreOptions.processorGeneration ? `A${restoreOptions.processorGeneration}` : 'Unknown'}</strong>
      </div>
    </section>

    {#if restoreOptions.warnings.length > 0}
      <section class="warnings">
        {#each restoreOptions.warnings as warning}
          <div>{warning}</div>
        {/each}
      </section>
    {/if}

    {#if errorMessage}
      <div class="error-state">{errorMessage}</div>
    {/if}

    <section class="panel">
      <div class="section-title">
        <span>1</span>
        <h2>Restore Path</h2>
      </div>
      <div class="options-list">
        {#each restoreOptions.options as option, index}
          <button
            class:active={index === selectedIndex}
            class="option-card"
            onclick={() => selectOption(index)}
          >
            <div class="option-main">
              <h3>{option.title}</h3>
              <p>{option.description}</p>
            </div>
            <div class="badges">
              {#if option.requiresBlobs}
                <span>SHSH</span>
              {/if}
              {#if option.requiresDfu}
                <span>DFU</span>
              {/if}
              {#if option.targetVersion}
                <span>{option.targetVersion}</span>
              {/if}
            </div>
          </button>
        {/each}
      </div>
    </section>

    <section class="panel">
      <div class="section-title">
        <span>2</span>
        <h2>IPSW</h2>
      </div>
      <div class="form-grid">
        <label>
          <span>Target IPSW Path</span>
          <input bind:value={ipswPath} placeholder="/path/to/firmware.ipsw" />
        </label>
        <label>
          <span>Expected SHA-1</span>
          <input bind:value={expectedSha1} placeholder="Optional" />
        </label>
      </div>
      <div class="actions">
        <button class="secondary" onclick={handleVerify} disabled={!canVerify}>Verify IPSW</button>
      </div>

      {#if verifyResult}
        <div
          class="verify-result"
          class:match={verifyResult.matches === true}
          class:mismatch={verifyResult.matches === false}
        >
          <span>{verifyResult.calculatedSha1}</span>
          {#if verifyResult.matches === true}
            <strong>Match</strong>
          {:else if verifyResult.matches === false}
            <strong>Mismatch</strong>
          {:else}
            <strong>Calculated</strong>
          {/if}
        </div>
      {/if}

      <div class="download-box">
        <div class="form-grid">
          <label>
            <span>Download URL</span>
            <input bind:value={downloadUrl} placeholder="https://...Restore.ipsw" />
          </label>
          <label>
            <span>Output Directory</span>
            <input bind:value={downloadDir} placeholder="/path/to/downloads" />
          </label>
          <label>
            <span>File Name</span>
            <input bind:value={downloadFileName} placeholder="Optional" />
          </label>
        </div>
        <div class="actions">
          <button class="secondary" onclick={handleDownload} disabled={isWorking || !downloadUrl || !downloadDir}>
            Download with aria2c
          </button>
        </div>
      </div>
    </section>

    {#if needsPrepStep}
      <section class="panel">
        <div class="section-title">
          <span>3</span>
          <h2>Prepare Custom IPSW</h2>
        </div>
        <p class="prep-note">
          powdersn0w will patch the source IPSW and write a custom IPSW to the output directory.
          The custom IPSW is then used automatically in the restore step.
        </p>
        <div class="form-grid">
          <label>
            <span>Output Directory</span>
            <input bind:value={prepOutputDir} placeholder="/path/to/output" />
          </label>
          {#if selectedOption?.requiresBlobs}
            <label>
              <span>SHSH Blob Path</span>
              <input bind:value={shshPath} placeholder="Required for blob-based restore" />
            </label>
          {/if}
        </div>
        <div class="actions">
          <button class="secondary" onclick={handlePrepareIpsw} disabled={!canPrep}>
            {isPreparing ? 'Preparing…' : 'Prepare Custom IPSW'}
          </button>
        </div>
        {#if prepResult}
          <div class="prep-result">
            <span>Output:</span>
            <code>{prepResult.outputPath}</code>
          </div>
        {/if}
      </section>
    {/if}

    <section class="panel">
      <div class="section-title">
        <span>{needsPrepStep ? '4' : '3'}</span>
        <h2>Restore Command</h2>
      </div>

      <div class="form-grid">
        <label>
          <span>Tool</span>
          <select bind:value={selectedTool}>
            <option value="ideviceRestore">idevicerestore</option>
            <option value="futureRestore">futurerestore</option>
          </select>
        </label>
        <label>
          <span>Target SHSH Path</span>
          <input bind:value={shshPath} placeholder="Required for futurerestore" />
        </label>
      </div>

      {#if selectedTool === 'ideviceRestore'}
        <div class="toggle-grid">
          <label><input type="checkbox" bind:checked={erase} disabled={update} /> Erase restore</label>
          <label><input type="checkbox" bind:checked={update} disabled={erase} /> Update restore</label>
        </div>
      {:else}
        <div class="toggle-grid">
          <label><input type="checkbox" bind:checked={noBaseband} /> No baseband</label>
          <label><input type="checkbox" bind:checked={latestSep} /> Latest SEP</label>
          <label><input type="checkbox" bind:checked={latestBaseband} /> Latest baseband</label>
          <label><input type="checkbox" bind:checked={usePwndfu} /> Use pwned DFU</label>
          <label><input type="checkbox" bind:checked={skipBlob} /> Skip blob</label>
          <label><input type="checkbox" bind:checked={setNonce} /> Set nonce only</label>
        </div>
      {/if}

      <div class="actions">
        <button class="secondary" onclick={() => handlePreview(true)} disabled={!canPreview}>Preview</button>
        <button class="danger" onclick={handleStartRestore} disabled={!canRun}>Start Restore</button>
      </div>

      {#if preview}
        <div class="command-preview">
          <code>{preview.binary} {preview.args.join(' ')}</code>
          {#if preview.warnings.length > 0}
            <div class="preview-warnings">
              {#each preview.warnings as warning}
                <span>{warning}</span>
              {/each}
            </div>
          {/if}
        </div>
      {/if}
    </section>
  {:else if errorMessage}
    <div class="error-state">{errorMessage}</div>
  {/if}
</div>

<style>
  .view {
    padding: var(--spacing-xl);
    max-width: 860px;
  }

  .view-header {
    margin-bottom: var(--spacing-lg);
  }

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
    grid-template-columns: repeat(2, minmax(0, 1fr));
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

  .options-list {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-sm);
  }

  .option-card {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: var(--spacing-md);
    width: 100%;
    background: var(--color-bg-primary);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    padding: var(--spacing-md);
    text-align: left;
  }

  .option-card.active {
    border-color: var(--color-accent);
    box-shadow: 0 0 0 1px var(--color-accent);
  }

  .option-main h3 {
    color: var(--color-text-primary);
    font-size: 0.95rem;
    font-weight: 600;
    margin: 0 0 4px;
  }

  .option-main p {
    color: var(--color-text-secondary);
    font-size: 0.8rem;
    line-height: 1.45;
    margin: 0;
  }

  .badges {
    display: flex;
    flex-wrap: wrap;
    justify-content: flex-end;
    gap: var(--spacing-xs);
    min-width: 96px;
  }

  .badges span,
  .verify-result strong {
    border-radius: var(--radius-sm);
    background: var(--color-bg-secondary);
    border: 1px solid var(--color-border);
    color: var(--color-text-secondary);
    font-size: 0.7rem;
    font-weight: 600;
    padding: 3px 6px;
  }

  .form-grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: var(--spacing-md);
  }

  label {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-xs);
    color: var(--color-text-secondary);
    font-size: 0.75rem;
    font-weight: 600;
  }

  input,
  select {
    width: 100%;
    border: 1px solid var(--color-border);
    border-radius: var(--radius-sm);
    background: var(--color-bg-primary);
    color: var(--color-text-primary);
    font: inherit;
    font-size: 0.85rem;
    padding: 8px 10px;
  }

  .download-box {
    border-top: 1px solid var(--color-border);
    margin-top: var(--spacing-md);
    padding-top: var(--spacing-md);
  }

  .toggle-grid {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: var(--spacing-sm);
  }

  .toggle-grid label {
    align-items: center;
    flex-direction: row;
    gap: var(--spacing-sm);
    min-height: 32px;
    border: 1px solid var(--color-border);
    border-radius: var(--radius-sm);
    background: var(--color-bg-primary);
    padding: 0 var(--spacing-sm);
  }

  .actions {
    display: flex;
    gap: var(--spacing-sm);
    justify-content: flex-end;
    margin-top: var(--spacing-md);
  }

  button.secondary,
  button.danger {
    border: 1px solid var(--color-border);
    border-radius: var(--radius-sm);
    font-size: 0.85rem;
    font-weight: 600;
    padding: 8px 12px;
  }

  button.secondary {
    background: var(--color-bg-primary);
    color: var(--color-text-primary);
  }

  button.danger {
    background: var(--color-danger);
    border-color: var(--color-danger);
    color: white;
  }

  button:disabled {
    cursor: not-allowed;
    opacity: 0.5;
  }

  .warnings,
  .preview-warnings {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-sm);
    margin-bottom: var(--spacing-md);
  }

  .warnings div,
  .error-state,
  .empty-state,
  .command-preview,
  .verify-result {
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    padding: var(--spacing-md);
    color: var(--color-text-primary);
    background: var(--color-bg-secondary);
    font-size: 0.875rem;
  }

  .warnings div {
    border-color: color-mix(in srgb, var(--color-warning) 45%, var(--color-border));
  }

  .error-state {
    border-color: color-mix(in srgb, var(--color-danger) 45%, var(--color-border));
    color: var(--color-danger);
    margin-bottom: var(--spacing-md);
  }

  .verify-result {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--spacing-md);
    margin-top: var(--spacing-md);
    word-break: break-all;
  }

  .verify-result.match {
    border-color: color-mix(in srgb, var(--color-success) 45%, var(--color-border));
  }

  .verify-result.mismatch {
    border-color: color-mix(in srgb, var(--color-danger) 45%, var(--color-border));
  }

  .command-preview {
    margin-top: var(--spacing-md);
  }

  .command-preview code {
    display: block;
    color: var(--color-text-primary);
    font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
    font-size: 0.78rem;
    overflow-wrap: anywhere;
  }

  .preview-warnings {
    margin: var(--spacing-md) 0 0;
  }

  .preview-warnings span {
    color: var(--color-warning);
    font-size: 0.8rem;
  }

  .prep-note {
    color: var(--color-text-secondary);
    font-size: 0.8rem;
    line-height: 1.5;
    margin: 0 0 var(--spacing-md);
  }

  .prep-result {
    display: flex;
    align-items: baseline;
    gap: var(--spacing-sm);
    border: 1px solid color-mix(in srgb, var(--color-success) 45%, var(--color-border));
    border-radius: var(--radius-md);
    background: var(--color-bg-secondary);
    padding: var(--spacing-md);
    margin-top: var(--spacing-md);
    font-size: 0.8rem;
    color: var(--color-text-secondary);
  }

  .prep-result code {
    color: var(--color-text-primary);
    font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
    font-size: 0.78rem;
    overflow-wrap: anywhere;
  }

  @media (max-width: 720px) {
    .device-summary,
    .form-grid,
    .toggle-grid {
      grid-template-columns: 1fr;
    }

    .option-card {
      flex-direction: column;
    }

    .badges,
    .actions {
      justify-content: flex-start;
    }
  }
</style>
