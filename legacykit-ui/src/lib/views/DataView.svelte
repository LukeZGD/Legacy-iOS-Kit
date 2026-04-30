<script lang="ts">
  // Svelte 5 - Data Management placeholder view
</script>

<div class="view">
  <div class="view-header">
    <h1>Data Management</h1>
    <span class="badge coming-soon">Coming Soon</span>
  </div>
  <p class="view-description">Backup and restore device data with granular control. Create full backups, perform selective restores, mount filesystems, and securely erase devices.</p>
  <div class="features-list">
    <h3>Planned Features</h3>
    <ul>
      <li>Full device backup</li>
      <li>Selective restore</li>
      <li>Mount filesystem</li>
      <li>Erase device</li>
    </ul>
  </div>
</div>

<style>
  .view { padding: var(--spacing-xl); }
  .view-header { display: flex; align-items: center; gap: var(--spacing-md); margin-bottom: var(--spacing-lg); }
  .view-header h1 { font-size: 1.5rem; font-weight: 700; color: var(--color-text-primary); margin: 0; }
  .badge.coming-soon {
    padding: var(--spacing-xs) var(--spacing-md);
    background: var(--color-accent);
    color: white;
    border-radius: 9999px;
    font-size: 0.75rem;
    font-weight: 600;
  }
  .view-description { color: var(--color-text-secondary); margin-bottom: var(--spacing-xl); line-height: 1.6; }
  .features-list h3 { font-size: 1rem; font-weight: 600; color: var(--color-text-primary); margin-bottom: var(--spacing-md); }
  .features-list ul { list-style: none; padding: 0; margin: 0; }
  .features-list li {
    padding: var(--spacing-sm) var(--spacing-md);
    background: var(--color-bg-secondary);
    border-radius: var(--radius-md);
    margin-bottom: var(--spacing-sm);
    color: var(--color-text-primary);
  }
  .features-list li::before { content: "→ "; color: var(--color-accent); font-weight: 600; }
</style>
