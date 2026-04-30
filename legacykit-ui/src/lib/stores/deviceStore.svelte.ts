export type DeviceMode = 'Normal' | 'Recovery' | 'DFU' | 'kDFU' | 'pwnDFU';

export interface DeviceInfo {
    connected: boolean;
    name: string | null;
    udid: string | null;
    ecid: string | null;
    serial: string | null;
    model: string | null;
    product_type: string | null;
    ios_version: string | null;
    mode: DeviceMode;
}

class DeviceStore {
    state = $state<DeviceInfo>({
        connected: false,
        name: null,
        udid: null,
        ecid: null,
        serial: null,
        model: null,
        product_type: null,
        ios_version: null,
        mode: 'Normal'
    });

    updateFromBackend(info: DeviceInfo) {
        this.state = { ...info };
    }

    setDevice(info: Partial<DeviceInfo>) {
        this.state = { ...this.state, ...info, connected: true };
    }

    clearDevice() {
        this.state = {
            connected: false,
            name: null,
            udid: null,
            ecid: null,
            serial: null,
            model: null,
            product_type: null,
            ios_version: null,
            mode: 'Normal'
        };
    }
}

export const deviceStore = new DeviceStore();
