<script lang="ts">
  import { deviceStore } from '$lib/stores/deviceStore.svelte';
  import { onDestroy } from 'svelte';

  type ButtonCombo = 'home' | 'volDown';

  interface Step {
    label: string;
    seconds: number;
  }

  const homeSteps: Step[] = [
    { label: 'Press and hold Power + Home', seconds: 4 },
    { label: 'Release Power, keep holding Home', seconds: 10 },
  ];

  const volDownSteps: Step[] = [
    { label: 'Press and hold Side + Volume Down', seconds: 4 },
    { label: 'Release Side, keep holding Volume Down', seconds: 10 },
  ];

  let combo = $derived<ButtonCombo>(detectCombo(deviceStore.state.product_type));
  let steps = $derived(combo === 'volDown' ? volDownSteps : homeSteps);
  let mode = $derived(deviceStore.state.mode);

  let activeStep = $state<number | null>(null);
  let remaining = $state(0);
  let timerHandle: number | null = null;

  function detectCombo(productType: string | null): ButtonCombo {
    if (!productType) return 'home';
    // iPhone 7 / 7 Plus (A10) use Volume Down instead of Home for DFU
    if (productType === 'iPhone9,1' || productType === 'iPhone9,2'
      || productType === 'iPhone9,3' || productType === 'iPhone9,4') {
      return 'volDown';
    }
    return 'home';
  }

  function startGuide() {
    cancelGuide();
    activeStep = 0;
    runStep(0);
  }

  function runStep(index: number) {
    if (index >= steps.length) {
      activeStep = null;
      return;
    }
    activeStep = index;
    remaining = steps[index].seconds;
    timerHandle = window.setInterval(() => {
      remaining -= 1;
      if (remaining <= 0) {
        if (timerHandle !== null) {
          window.clearInterval(timerHandle);
          timerHandle = null;
        }
        runStep(index + 1);
      }
    }, 1000);
  }

  function cancelGuide() {
    if (timerHandle !== null) {
      window.clearInterval(timerHandle);
      timerHandle = null;
    }
    activeStep = null;
    remaining = 0;
  }

  onDestroy(cancelGuide);
</script>

<div class="dfu-helper">
  <header>
    <div>
      <h3>DFU Mode Helper</h3>
      <p>
        {combo === 'volDown'
          ? 'Detected iPhone 7-era device. Use the Side + Volume Down combo.'
          : 'Use the Home + Power combo to enter DFU mode.'}
      </p>
    </div>
    <span class="mode-pill" class:dfu={mode === 'DFU' || mode === 'pwnDFU'}>
      {mode}
    </span>
  </header>

  <ol class="steps">
    {#each steps as step, index}
      <li class:active={activeStep === index} class:done={activeStep !== null && activeStep > index}>
        <span class="bullet">{index + 1}</span>
        <div class="step-body">
          <span class="step-label">{step.label}</span>
          <span class="step-time">
            {#if activeStep === index}
              {remaining}s remaining
            {:else}
              {step.seconds}s
            {/if}
          </span>
        </div>
      </li>
    {/each}
    <li class:done={mode === 'DFU' || mode === 'pwnDFU'}>
      <span class="bullet">{steps.length + 1}</span>
      <div class="step-body">
        <span class="step-label">Screen stays black — device should be in DFU mode</span>
      </div>
    </li>
  </ol>

  <div class="actions">
    {#if activeStep === null}
      <button class="primary" onclick={startGuide}>Start guided timer</button>
    {:else}
      <button class="secondary" onclick={cancelGuide}>Cancel</button>
    {/if}
  </div>
</div>

<style>
  .dfu-helper {
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    background: var(--color-bg-secondary);
    padding: var(--spacing-md);
  }

  header {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    gap: var(--spacing-md);
    margin-bottom: var(--spacing-md);
  }

  header h3 {
    color: var(--color-text-primary);
    font-size: 0.95rem;
    font-weight: 600;
    margin: 0 0 4px;
  }

  header p {
    color: var(--color-text-secondary);
    font-size: 0.8rem;
    line-height: 1.45;
    margin: 0;
  }

  .mode-pill {
    border: 1px solid var(--color-border);
    border-radius: 9999px;
    background: var(--color-bg-primary);
    color: var(--color-text-secondary);
    font-size: 0.7rem;
    font-weight: 600;
    padding: 4px 10px;
    white-space: nowrap;
  }

  .mode-pill.dfu {
    border-color: color-mix(in srgb, var(--color-success) 55%, var(--color-border));
    color: var(--color-success);
  }

  .steps {
    list-style: none;
    padding: 0;
    margin: 0 0 var(--spacing-md);
    display: flex;
    flex-direction: column;
    gap: var(--spacing-sm);
  }

  .steps li {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-sm);
    background: var(--color-bg-primary);
    padding: var(--spacing-sm) var(--spacing-md);
  }

  .steps li.active {
    border-color: var(--color-accent);
    box-shadow: 0 0 0 1px var(--color-accent);
  }

  .steps li.done {
    border-color: color-mix(in srgb, var(--color-success) 45%, var(--color-border));
    opacity: 0.85;
  }

  .bullet {
    display: inline-grid;
    place-items: center;
    width: 22px;
    height: 22px;
    border-radius: 50%;
    background: var(--color-bg-secondary);
    color: var(--color-text-secondary);
    font-size: 0.72rem;
    font-weight: 700;
    flex-shrink: 0;
  }

  .steps li.active .bullet {
    background: var(--color-accent);
    color: white;
  }

  .steps li.done .bullet {
    background: var(--color-success);
    color: white;
  }

  .step-body {
    flex: 1;
    display: flex;
    justify-content: space-between;
    gap: var(--spacing-sm);
    align-items: center;
  }

  .step-label {
    color: var(--color-text-primary);
    font-size: 0.85rem;
  }

  .step-time {
    color: var(--color-text-secondary);
    font-size: 0.72rem;
    font-variant-numeric: tabular-nums;
  }

  .actions {
    display: flex;
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
</style>
