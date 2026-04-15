export interface NativePlayerCapability {
  available: boolean;
  version: string;
  features: string[];
  backendName?: string;
  blocker?: string;
  stage?: string;
}

export interface NativePlayerMetrics {
  bufferedDurationMs: number;
  decodedAudioFrames: number;
  decodedVideoFrames: number;
  renderedAudioFrames: number;
  renderedVideoFrames: number;
  droppedVideoFrames: number;
  audioClockMs: number;
  videoClockMs: number;
  packetQueueDepth: number;
  audioQueueDepth: number;
  videoQueueDepth: number;
  emittedEvents: number;
}

export interface NativePlayerStateSnapshot {
  state: string;
  source: string;
  surfaceId: string;
  positionMs: number;
  lastError: string;
  stage?: string;
  errorStage?: string;
  metrics?: NativePlayerMetrics;
}

export interface NativePlayerEvent {
  type: string;
  message: string;
  state: string;
  source: string;
  surfaceId: string;
  positionMs: number;
  lastError: string;
  backendName: string;
  stage?: string;
  errorStage?: string;
  metrics?: NativePlayerMetrics;
}

export type NativePlayerEventListener = (event: NativePlayerEvent) => void;

interface NativePlayerBridge {
  getCapability?: () => NativePlayerCapability;
  getState?: () => NativePlayerStateSnapshot;
  setEventListener?: (listener: NativePlayerEventListener) => void;
  clearEventListener?: () => void;
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
      features: ['bridge-skeleton'],
      backendName: 'unloaded',
      blocker: 'Native bridge module is unavailable',
      stage: 'unloaded'
    };
  }

  isAvailable(): boolean {
    return this.getCapability().available;
  }

  getState(): NativePlayerStateSnapshot {
    return this.bridge?.getState?.() ?? {
      state: 'unloaded',
      source: '',
      surfaceId: '',
      positionMs: 0,
      lastError: '',
      stage: 'unloaded',
      errorStage: '',
      metrics: {
        bufferedDurationMs: 0,
        decodedAudioFrames: 0,
        decodedVideoFrames: 0,
        renderedAudioFrames: 0,
        renderedVideoFrames: 0,
        droppedVideoFrames: 0,
        audioClockMs: 0,
        videoClockMs: 0,
        packetQueueDepth: 0,
        audioQueueDepth: 0,
        videoQueueDepth: 0,
        emittedEvents: 0
      }
    };
  }

  setEventListener(listener: NativePlayerEventListener): void {
    this.bridge?.setEventListener?.(listener);
  }

  clearEventListener(): void {
    this.bridge?.clearEventListener?.();
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
