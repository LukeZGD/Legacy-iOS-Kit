<script lang="ts">
  import {
    extractIpswComponent,
    modifyRamdisk,
    packImg4,
    patchIboot,
    patchKernel,
    repackImg3,
    type IbootBitWidth,
  } from '$lib/api/firmware';
  import { runKloader } from '$lib/api/jailbreak';
  import { deviceStore } from '$lib/stores/deviceStore.svelte';
  import { logStore } from '$lib/stores/logStore.svelte';

  let ipswPath = $state('');
  let outputDir = $state('');
  let bootArgs = $state('rd=md0 -v amfi_get_out_of_my_way=0x1 cs_enforcement_disable=1');
  let ibssIpswPath = $state('');
  let ibecIpswPath = $state('');
  let kernelIpswPath = $state('');
  let ramdiskIpswPath = $state('');
  let shshPath = $state('');
  let sshBinariesDir = $state('');
  let ramdiskTargetSizeMb = $state(35);

  let extractedIbss = $state('');
  let extractedIbec = $state('');
  let extractedKernel = $state('');
  let extractedRamdisk = $state('');
  let patchedIbss = $state('');
  let patchedIbec = $state('');
  let patchedKernel = $state('');

  let isWorking = $state(false);
  let errorMessage = $state<string | null>(null);

  let productType = $derived(deviceStore.state.product_type);
  let processorGen = $derived(inferProcessorGen(productType));
  let bitWidth = $derived<IbootBitWidth>(processorGen !== null && processorGen >= 7 ? 'bits64' : 'bits32');
  let mode = $derived(deviceStore.state.mode);

  function inferProcessorGen(product: string | null): number | null {
    if (!product) return null;
    if (/^iPhone(1|2),/.test(product) || /^iPod(1|2),/.test(product)) return 1;
    if (product === 'iPod3,1') return 3;
    if (/^iPhone3,/.test(product) || product === 'iPad1,1' || product === 'iPod4,1') return 4;
    if (product === 'iPhone4,1' || /^iPad2,/.test(product) || /^iPad3,[1-3]/.test(product) || product === 'iPod5,1') return 5;
    if (/^iPhone5,/.test(product) || /^iPad3,[4-6]/.test(product)) return 6;
    if (/^iPhone6,/.test(product) || /^iPad4,/.test(product)) return 7;
    if (/^iPhone7,/.test(product) || product === 'iPod7,1' || /^iPad5,/.test(product)) return 8;
    if (/^iPhone8,/.test(product) || /^iPad6,/.test(product)) return 9;
    if (/^iPhone9,/.test(product) || /^iPad7,/.test(product)) return 10;
    return null;
  }

  function joinOut(name: string): string {
    const dir = outputDir.replace(/\/$/, '');
    return `${dir}/${name}`;
  }

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

  async function handleExtractAll() {
    if (!ipswPath || !outputDir) {
      errorMessage = 'Source IPSW and output directory are required.';
      return;
    }

    const targets: Array<{ entry: string; out: string; setter: (v: string) => void }> = [
      { entry: ibssIpswPath, out: joinOut('iBSS.bin'), setter: (v) => (extractedIbss = v) },
      { entry: ibecIpswPath, out: joinOut('iBEC.bin'), setter: (v) => (extractedIbec = v) },
      { entry: kernelIpswPath, out: joinOut('kernelcache.bin'), setter: (v) => (extractedKernel = v) },
      { entry: ramdiskIpswPath, out: joinOut('ramdisk.dmg'), setter: (v) => (extractedRamdisk = v) },
    ];

    for (const target of targets) {
      if (!target.entry.trim()) continue;
      const result = await withWorking(`Extracting ${target.entry}`, () =>
        extractIpswComponent({ ipswPath, componentPath: target.entry, outputPath: target.out })
      );
      if (!result) return;
      target.setter(result.outputPath);
    }
  }

  async function handlePatchIboots() {
    if (!extractedIbss || !extractedIbec) {
      errorMessage = 'Extract iBSS and iBEC first.';
      return;
    }

    const ibssOut = joinOut('iBSS.patched.bin');
    const ibecOut = joinOut('iBEC.patched.bin');

    const ibssResult = await withWorking('Patching iBSS', () =>
      patchIboot({
        inputPath: extractedIbss,
        outputPath: ibssOut,
        bitWidth,
        bootArgs: null,
        bypassRsa: true,
        debug: false,
      })
    );
    if (!ibssResult) return;
    patchedIbss = ibssResult.outputPath;

    const ibecResult = await withWorking('Patching iBEC', () =>
      patchIboot({
        inputPath: extractedIbec,
        outputPath: ibecOut,
        bitWidth,
        bootArgs: bootArgs || null,
        bypassRsa: true,
        debug: false,
      })
    );
    if (!ibecResult) return;
    patchedIbec = ibecResult.outputPath;
  }

  async function handlePatchKernel() {
    if (!extractedKernel) {
      errorMessage = 'Extract the kernelcache first.';
      return;
    }
    const out = joinOut('kernelcache.patched.bin');
    const result = await withWorking('Patching kernel', () =>
      patchKernel({
        inputPath: extractedKernel,
        outputPath: out,
        bitWidth,
        flags: ['-a', '-f'],
      })
    );
    if (!result) return;
    patchedKernel = result.outputPath;
  }

  async function handleResizeRamdisk() {
    if (!extractedRamdisk) {
      errorMessage = 'Extract the ramdisk first.';
      return;
    }
    await withWorking(`Growing ramdisk to ${ramdiskTargetSizeMb} MB`, () =>
      modifyRamdisk({
        ramdiskPath: extractedRamdisk,
        action: 'resize',
        sourcePath: null,
        targetPath: null,
        sizeMb: ramdiskTargetSizeMb,
      })
    );
  }

  async function handleInjectSshBinaries() {
    if (!extractedRamdisk) {
      errorMessage = 'Extract the ramdisk first.';
      return;
    }
    if (!sshBinariesDir.trim()) {
      errorMessage = 'Provide a directory of SSH binaries to inject.';
      return;
    }

    const binaries = [
      { local: 'dropbear', target: '/usr/local/bin/dropbear' },
      { local: 'authorized_keys', target: '/var/root/.ssh/authorized_keys' },
    ];
    const baseDir = sshBinariesDir.replace(/\/$/, '');

    for (const bin of binaries) {
      const localPath = `${baseDir}/${bin.local}`;
      const result = await withWorking(`Injecting ${bin.local}`, () =>
        modifyRamdisk({
          ramdiskPath: extractedRamdisk,
          action: 'add',
          sourcePath: localPath,
          targetPath: bin.target,
          sizeMb: null,
        })
      );
      if (!result) return;
    }
  }

  async function handleRepackComponent(label: string, inputPath: string, outName: string) {
    const out = joinOut(outName);
    if (bitWidth === 'bits64') {
      const result = await withWorking(`Packing ${label} as IMG4`, () =>
        packImg4({
          im4pPath: inputPath,
          outputPath: out,
          shshPath: shshPath || null,
          im4mPath: null,
        })
      );
      return result?.outputPath ?? null;
    }
    const result = await withWorking(`Repacking ${label} as IMG3`, () =>
      repackImg3({
        inputPath,
        outputPath: out,
        templatePath: null,
        key: null,
        iv: null,
      })
    );
    return result?.outputPath ?? null;
  }

  async function handleRepackAll() {
    if (patchedIbss) {
      const repacked = await handleRepackComponent('iBSS', patchedIbss, 'iBSS.repacked');
      if (repacked) patchedIbss = repacked;
    }
    if (patchedIbec) {
      const repacked = await handleRepackComponent('iBEC', patchedIbec, 'iBEC.repacked');
      if (repacked) patchedIbec = repacked;
    }
    if (patchedKernel) {
      const repacked = await handleRepackComponent('kernelcache', patchedKernel, 'kernelcache.repacked');
      if (repacked) patchedKernel = repacked;
    }
  }

  async function handleBoot() {
    if (!patchedIbss) {
      errorMessage = 'Patched iBSS is required for kloader.';
      return;
    }
    await withWorking('Booting via kloader', () =>
      runKloader({ ibssPath: patchedIbss, ibecPath: patchedIbec || null })
    );
  }
</script>

<div class="view">
  <div class="view-header">
    <div>
      <h1>SSH Ramdisk</h1>
      <p>Build and boot a custom SSH ramdisk in stages. Each step writes its output to your output directory and feeds the next.</p>
    </div>
  </div>

  <section class="device-summary">
    <div>
      <span class="label">Device</span>
      <strong>{productType ?? 'Not detected'}</strong>
    </div>
    <div>
      <span class="label">Bit width</span>
      <strong>{bitWidth === 'bits64' ? '64-bit (IMG4)' : '32-bit (IMG3)'}</strong>
    </div>
    <div>
      <span class="label">Mode</span>
      <strong>{mode}</strong>
    </div>
  </section>

  {#if errorMessage}
    <div class="error-state">{errorMessage}</div>
  {/if}

  <section class="panel">
    <div class="section-title">
      <span>1</span>
      <h2>Inputs</h2>
    </div>
    <div class="form-grid">
      <label>
        <span>Source IPSW</span>
        <input bind:value={ipswPath} placeholder="/path/to/firmware.ipsw" />
      </label>
      <label>
        <span>Output Directory</span>
        <input bind:value={outputDir} placeholder="/path/to/work" />
      </label>
      <label>
        <span>Boot Args</span>
        <input bind:value={bootArgs} />
      </label>
      <label>
        <span>SHSH (IMG4 packing)</span>
        <input bind:value={shshPath} placeholder="Optional, 64-bit only" />
      </label>
    </div>
    <div class="form-grid">
      <label>
        <span>iBSS path in IPSW</span>
        <input bind:value={ibssIpswPath} placeholder="Firmware/dfu/iBSS.<board>.RELEASE.dfu" />
      </label>
      <label>
        <span>iBEC path in IPSW</span>
        <input bind:value={ibecIpswPath} placeholder="Firmware/dfu/iBEC.<board>.RELEASE.dfu" />
      </label>
      <label>
        <span>Kernelcache path in IPSW</span>
        <input bind:value={kernelIpswPath} placeholder="kernelcache.release.<chip>" />
      </label>
      <label>
        <span>Ramdisk path in IPSW</span>
        <input bind:value={ramdiskIpswPath} placeholder="<ramdisk>.dmg" />
      </label>
    </div>
  </section>

  <section class="panel">
    <div class="section-title">
      <span>2</span>
      <h2>Extract Components</h2>
    </div>
    <div class="actions">
      <button class="primary" onclick={handleExtractAll} disabled={isWorking}>
        Extract all
      </button>
    </div>
    <ul class="paths">
      <li><span>iBSS:</span><code>{extractedIbss || '—'}</code></li>
      <li><span>iBEC:</span><code>{extractedIbec || '—'}</code></li>
      <li><span>Kernel:</span><code>{extractedKernel || '—'}</code></li>
      <li><span>Ramdisk:</span><code>{extractedRamdisk || '—'}</code></li>
    </ul>
  </section>

  <section class="panel">
    <div class="section-title">
      <span>3</span>
      <h2>Patch iBSS &amp; iBEC</h2>
    </div>
    <p class="panel-note">
      Applies signature bypass and injects boot args. iBEC carries the boot args for the kernel.
    </p>
    <div class="actions">
      <button class="secondary" onclick={handlePatchIboots} disabled={isWorking}>
        Patch iBoot
      </button>
    </div>
    <ul class="paths">
      <li><span>iBSS:</span><code>{patchedIbss || '—'}</code></li>
      <li><span>iBEC:</span><code>{patchedIbec || '—'}</code></li>
    </ul>
  </section>

  <section class="panel">
    <div class="section-title">
      <span>4</span>
      <h2>Patch Kernel</h2>
    </div>
    <p class="panel-note">Applies AMFI bypass (`-a`) and force-load (`-f`) flags.</p>
    <div class="actions">
      <button class="secondary" onclick={handlePatchKernel} disabled={isWorking}>
        Patch kernel
      </button>
    </div>
    <ul class="paths">
      <li><span>Kernel:</span><code>{patchedKernel || '—'}</code></li>
    </ul>
  </section>

  <section class="panel">
    <div class="section-title">
      <span>5</span>
      <h2>Modify Ramdisk</h2>
    </div>
    <div class="form-grid">
      <label>
        <span>Target Size (MB)</span>
        <input type="number" min="10" bind:value={ramdiskTargetSizeMb} />
      </label>
      <label>
        <span>SSH binaries directory</span>
        <input bind:value={sshBinariesDir} placeholder="Folder with dropbear, authorized_keys, …" />
      </label>
    </div>
    <div class="actions">
      <button class="secondary" onclick={handleResizeRamdisk} disabled={isWorking}>Grow ramdisk</button>
      <button class="secondary" onclick={handleInjectSshBinaries} disabled={isWorking}>Inject SSH binaries</button>
    </div>
  </section>

  <section class="panel">
    <div class="section-title">
      <span>6</span>
      <h2>Repack Components</h2>
    </div>
    <p class="panel-note">
      Wraps patched iBSS/iBEC/kernel as {bitWidth === 'bits64' ? 'IMG4' : 'IMG3'}.
      Required before kloader can hand them off to the device.
    </p>
    <div class="actions">
      <button class="secondary" onclick={handleRepackAll} disabled={isWorking}>Repack all</button>
    </div>
  </section>

  <section class="panel">
    <div class="section-title">
      <span>7</span>
      <h2>Boot</h2>
    </div>
    <p class="panel-note">
      Device must be in pwned DFU. Use the Jailbreak view to run gaster first if needed.
    </p>
    <div class="actions">
      <button class="primary" onclick={handleBoot} disabled={isWorking || (mode !== 'DFU' && mode !== 'pwnDFU')}>
        kloader iBSS &rarr; iBEC
      </button>
    </div>
  </section>
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

  .form-grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: var(--spacing-md);
    margin-bottom: var(--spacing-md);
  }

  label {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-xs);
    color: var(--color-text-secondary);
    font-size: 0.75rem;
    font-weight: 600;
  }

  input {
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
    margin-bottom: var(--spacing-sm);
  }

  button {
    border: 1px solid var(--color-border);
    border-radius: var(--radius-sm);
    font-size: 0.85rem;
    font-weight: 600;
    padding: 8px 12px;
  }

  button.primary {
    background: var(--color-accent);
    border-color: var(--color-accent);
    color: white;
  }

  button.secondary {
    background: var(--color-bg-primary);
    color: var(--color-text-primary);
  }

  button:disabled {
    cursor: not-allowed;
    opacity: 0.5;
  }

  .paths {
    list-style: none;
    padding: 0;
    margin: 0;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .paths li {
    display: flex;
    gap: var(--spacing-sm);
    align-items: baseline;
    font-size: 0.78rem;
    color: var(--color-text-secondary);
  }

  .paths li span {
    flex-shrink: 0;
    width: 70px;
    color: var(--color-text-primary);
  }

  .paths code {
    color: var(--color-text-primary);
    font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
    overflow-wrap: anywhere;
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

  @media (max-width: 720px) {
    .device-summary,
    .form-grid {
      grid-template-columns: 1fr;
    }

    .actions {
      justify-content: flex-start;
    }
  }
</style>
