<script lang="ts">
  import DfuHelper from '$lib/components/device/DfuHelper.svelte';
  import {
    runEvasi0n,
    runG1lbertJB,
    runGaster,
    type GasterAction,
  } from '$lib/api/jailbreak';
  import { deviceStore } from '$lib/stores/deviceStore.svelte';
  import { logStore } from '$lib/stores/logStore.svelte';

  type UntetherTool = 'g1lbertJB' | 'evasi0n';

  let isWorking = $state(false);
  let lastAction = $state<GasterAction | null>(null);
  let errorMessage = $state<string | null>(null);
  let untetherFlags = $state('');

  let mode = $derived(deviceStore.state.mode);
  let productType = $derived(deviceStore.state.product_type);
  let processorGen = $derived(inferProcessorGen(productType));
  let isCheckm8Eligible = $derived(processorGen !== null && processorGen >= 7 && processorGen <= 10);
  let isG1lbertEligible = $derived(processorGen !== null && processorGen >= 4 && processorGen <= 5);
  let isEvasi0nEligible = $derived(processorGen !== null && processorGen >= 5 && processorGen <= 6);

  function inferProcessorGen(product: string | null): number | null {
    if (!product) return null;
    if (/^iPhone3,/.test(product) || product === 'iPad1,1' || product === 'iPod4,1') return 4;
    if (product === 'iPhone4,1' || /^iPad2,/.test(product) || /^iPad3,[1-3]/.test(product) || product === 'iPod5,1') return 5;
    if (/^iPhone5,/.test(product) || /^iPad3,[4-6]/.test(product)) return 6;
    if (/^iPhone6,/.test(product) || /^iPad4,/.test(product)) return 7;
    if (/^iPhone7,/.test(product) || product === 'iPod7,1' || /^iPad5,/.test(product)) return 8;
    if (/^iPhone8,/.test(product) || /^iPad6,/.test(product)) return 9;
    if (/^iPhone9,/.test(product) || /^iPad7,/.test(product)) return 10;
    return null;
  }

  async function handleGaster(action: GasterAction) {
    isWorking = true;
    errorMessage = null;
    logStore.append(`Running gaster ${action}...`, 'info');

    try {
      const result = await runGaster({ action });
      lastAction = result.action;
      logStore.append(`gaster ${action} completed`, 'info');
    } catch (error) {
      errorMessage = error instanceof Error ? error.message : String(error);
      logStore.append(`gaster ${action} failed: ${errorMessage}`, 'stderr');
    } finally {
      isWorking = false;
    }
  }

  async function handleUntether(tool: UntetherTool) {
    isWorking = true;
    errorMessage = null;
    const extraArgs = untetherFlags.trim().split(/\s+/).filter(Boolean);
    logStore.append(`Running ${tool} ${extraArgs.join(' ')}...`, 'info');

    try {
      if (tool === 'g1lbertJB') {
        await runG1lbertJB({ extraArgs });
      } else {
        await runEvasi0n({ extraArgs });
      }
      logStore.append(`${tool} completed`, 'info');
    } catch (error) {
      errorMessage = error instanceof Error ? error.message : String(error);
      logStore.append(`${tool} failed: ${errorMessage}`, 'stderr');
    } finally {
      isWorking = false;
    }
  }
</script>

<div class="view">
  <div class="view-header">
    <div>
      <h1>Jailbreak</h1>
      <p>Enter pwned DFU with checkm8, then run an exploit chain.</p>
    </div>
  </div>

  <section class="device-summary">
    <div>
      <span class="label">Device</span>
      <strong>{productType ?? 'Not detected'}</strong>
    </div>
    <div>
      <span class="label">Processor</span>
      <strong>{processorGen ? `A${processorGen}` : 'Unknown'}</strong>
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
      <h2>Enter DFU Mode</h2>
    </div>
    <DfuHelper />
  </section>

  <section class="panel">
    <div class="section-title">
      <span>2</span>
      <h2>checkm8 (gaster)</h2>
    </div>
    <p class="panel-note">
      Runs the gaster binary against a device in DFU mode to enter pwned DFU.
      Supported on A7–A10 devices (iPhone 5s through iPhone 7, plus matching iPads/iPods).
    </p>

    {#if !isCheckm8Eligible && productType}
      <div class="warning">
        {productType} is not in the checkm8-supported range (A7–A10). Use g1lbertJB or evasi0n for older devices.
      </div>
    {/if}

    {#if mode !== 'DFU' && mode !== 'pwnDFU'}
      <div class="warning">
        Device must be in DFU mode before running gaster. Use the helper above to enter DFU.
      </div>
    {/if}

    <div class="actions">
      <button
        class="primary"
        onclick={() => handleGaster('pwn')}
        disabled={isWorking || mode !== 'DFU'}
      >
        {isWorking && lastAction !== 'reset' ? 'Running…' : 'gaster pwn'}
      </button>
      <button
        class="secondary"
        onclick={() => handleGaster('reset')}
        disabled={isWorking}
      >
        gaster reset
      </button>
    </div>
  </section>

  <section class="panel">
    <div class="section-title">
      <span>3</span>
      <h2>Untether</h2>
    </div>
    <p class="panel-note">
      g1lbertJB targets A4/A5 devices on iOS 5; evasi0n targets A5/A6 devices on iOS 6.
      Device must be in Normal mode and trusted before running either tool.
    </p>

    <label class="extra-args">
      <span>Extra flags</span>
      <input bind:value={untetherFlags} placeholder="Optional, passed verbatim (e.g. -v)" />
    </label>

    <div class="actions">
      <button
        class="secondary"
        onclick={() => handleUntether('g1lbertJB')}
        disabled={isWorking || mode !== 'Normal'}
      >
        Run g1lbertJB
      </button>
      <button
        class="secondary"
        onclick={() => handleUntether('evasi0n')}
        disabled={isWorking || mode !== 'Normal'}
      >
        Run evasi0n
      </button>
    </div>

    {#if productType && !isG1lbertEligible && !isEvasi0nEligible}
      <div class="warning">
        {productType} is outside the typical g1lbertJB / evasi0n device range. The tools may still run, but compatibility is not guaranteed.
      </div>
    {/if}
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

  .warning {
    border: 1px solid color-mix(in srgb, var(--color-warning) 45%, var(--color-border));
    border-radius: var(--radius-sm);
    background: var(--color-bg-primary);
    color: var(--color-text-primary);
    font-size: 0.8rem;
    padding: var(--spacing-sm) var(--spacing-md);
    margin-bottom: var(--spacing-md);
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

  .extra-args {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-xs);
    color: var(--color-text-secondary);
    font-size: 0.75rem;
    font-weight: 600;
    margin-bottom: var(--spacing-md);
  }

  .extra-args input {
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
</style>
