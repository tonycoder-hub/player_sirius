export interface NativePlayerCapability {
  available: boolean;
  version: string;
  features: string[];
}

interface NativePlayerBridge {
  getCapability?: () => NativePlayerCapability;
  prepare?: (source: string, surfaceId?: string) => number;
  play?: () => void;
  pause?: () => void;
  stop?: () => void;
  seek?: (positionMs: number) => void;
  release?: () => void;
}

export class NativePlayerBridgeService {
  private bridge: NativePlayerBridge | null = null;

  constructor() {
    this.bridge = this.tryLoadBridge();
  }

  getCapability(): NativePlayerCapability {
    return this.bridge?.getCapability?.() ?? {
      available: false,
      version: 'stub',
      features: ['bridge-skeleton']
    };
  }

  isAvailable(): boolean {
    return this.getCapability().available;
  }

  prepare(source: string, surfaceId: string = ''): boolean {
    if (!this.bridge?.prepare) {
      return false;
    }
    return this.bridge.prepare(source, surfaceId) === 0;
  }

  play(): void {
    this.bridge?.play?.();
  }

  pause(): void {
    this.bridge?.pause?.();
  }

  stop(): void {
    this.bridge?.stop?.();
  }

  seek(positionMs: number): void {
    this.bridge?.seek?.(positionMs);
  }

  release(): void {
    this.bridge?.release?.();
  }

  private tryLoadBridge(): NativePlayerBridge | null {
    try {
      const maybeLoader = (globalThis as Record<string, (name: string) => NativePlayerBridge>).requireNapi;
      if (typeof maybeLoader === 'function') {
        return maybeLoader('native_player_bridge');
      }
    } catch (err) {
      console.warn(`Native bridge unavailable: ${err}`);
    }
    return null;
  }
}

