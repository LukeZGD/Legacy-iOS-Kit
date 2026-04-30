export interface LogEntry {
    text: string;
    type: 'stdout' | 'stderr' | 'info';
    timestamp: number;
}

class LogStore {
    logs = $state<LogEntry[]>([]);

    append(text: string, type: 'stdout' | 'stderr' | 'info' = 'stdout') {
        this.logs.push({ text, type, timestamp: Date.now() });
    }

    clear() {
        this.logs = [];
    }
}

export const logStore = new LogStore();
