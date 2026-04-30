class SettingsStore {
  theme = $state<'system' | 'light' | 'dark'>('system');
  terminalVisible = $state<boolean>(true);
  terminalHeight = $state<number>(200);
  autoDetectDevice = $state<boolean>(true);
  pollIntervalMs = $state<number>(3000);

  setTheme(theme: 'system' | 'light' | 'dark') {
    this.theme = theme;
  }

  toggleTerminal() {
    this.terminalVisible = !this.terminalVisible;
  }

  setTerminalHeight(height: number) {
    this.terminalHeight = Math.max(100, Math.min(600, height));
  }

  setPollInterval(ms: number) {
    this.pollIntervalMs = Math.max(1000, ms);
  }
}

export const settingsStore = new SettingsStore();
