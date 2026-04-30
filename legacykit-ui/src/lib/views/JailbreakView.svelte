<script lang="ts">
  const features = [
    'checkm8 exploit',
    'g1lbertJB',
    'evasi0n',
    'Untethered jailbreak support',
  ];
</script>

<div class="view">
  <div class="view-header">
    <h1>Jailbreak</h1>
    <span class="badge coming-soon">Coming Soon</span>
  </div>
  <p class="view-description">
    Jailbreak legacy iOS devices with support for multiple exploits and jailbreak tools.
    Covers A4–A7 devices running iOS 3 through iOS 10.
  </p>
  <div class="features-list">
    <h3>Planned Features</h3>
    <ul>
      {#each features as feature}
        <li>{feature}</li>
      {/each}
    </ul>
  </div>
</div>

<style>
  .view { padding: var(--spacing-lg); }
  .view-header { display: flex; align-items: center; gap: var(--spacing-md); margin-bottom: var(--spacing-md); }
  .view-header h1 { font-size: 1.5rem; font-weight: 700; color: var(--color-text-primary); }
  .badge.coming-soon {
    padding: var(--spacing-xs) var(--spacing-md);
    background: var(--color-accent);
    color: white;
    border-radius: 9999px;
    font-size: 0.75rem;
    font-weight: 600;
  }
  .view-description { color: var(--color-text-secondary); margin-bottom: var(--spacing-lg); line-height: 1.6; }
  .features-list h3 { font-size: 1rem; font-weight: 600; color: var(--color-text-primary); margin-bottom: var(--spacing-md); }
  .features-list ul { list-style: none; padding: 0; margin: 0; }
  .features-list li {
    padding: var(--spacing-sm) var(--spacing-md);
    background: var(--color-bg-secondary);
    border-radius: var(--radius-md);
    margin-bottom: var(--spacing-sm);
    color: var(--color-text-primary);
    font-size: 0.875rem;
  }
  .features-list li::before { content: "→ "; color: var(--color-accent); font-weight: 600; }
</style>
