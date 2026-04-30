// Navigation views that match the sidebar items
export type ViewName = 
  | 'home'
  | 'restore'
  | 'jailbreak'
  | 'shsh'
  | 'ssh-ramdisk'
  | 'apps'
  | 'data'
  | 'utilities'
  | 'settings';

class NavigationStore {
  currentView = $state<ViewName>('home');
  previousView = $state<ViewName | null>(null);

  navigate(view: ViewName) {
    this.previousView = this.currentView;
    this.currentView = view;
  }

  goBack() {
    if (this.previousView) {
      this.currentView = this.previousView;
      this.previousView = null;
    }
  }
}

export const navigationStore = new NavigationStore();
