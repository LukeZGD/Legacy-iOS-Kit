export type ActionStatus = 'idle' | 'running' | 'success' | 'error';

class ActionStore {
    status = $state<ActionStatus>('idle');
    currentAction = $state<string | null>(null);
    error = $state<string | null>(null);

    start(actionName: string) {
        this.status = 'running';
        this.currentAction = actionName;
        this.error = null;
    }

    success() {
        this.status = 'success';
    }

    fail(errorMessage: string) {
        this.status = 'error';
        this.error = errorMessage;
    }

    reset() {
        this.status = 'idle';
        this.currentAction = null;
        this.error = null;
    }
}

export const actionStore = new ActionStore();
