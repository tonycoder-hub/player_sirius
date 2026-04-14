import { AVPlayer, AVPlayerState, AVPlayerEvents } from '@kit.MediaKit';
import { BusinessError } from '@kit.BasicServicesKit';

export class PlayerService {
  private avPlayer: AVPlayer | null = null;
  private isInitialized: boolean = false;
  private stateChangeListener: ((state: AVPlayerState) => void) | null = null;
  private timeUpdateListener: ((time: number, duration: number) => void) | null = null;

  constructor() {}

  async init(): Promise<void> {
    try {
      this.avPlayer = await AVPlayer.create();
      this.setupEventListeners();
      this.isInitialized = true;
    } catch (err) {
      const error = err as BusinessError;
      console.error(`PlayerService init failed: ${error.code}, ${error.message}`);
      throw error;
    }
  }

  private setupEventListeners(): void {
    if (!this.avPlayer) {
      return;
    }

    this.avPlayer.on('stateChange', (state: AVPlayerState) => {
      console.info(`Player state changed: ${state}`);
      if (this.stateChangeListener) {
        this.stateChangeListener(state);
      }
    });

    this.avPlayer.on('timeUpdate', (timeInfo: { currentTime: number; duration: number }) => {
      if (this.timeUpdateListener) {
        this.timeUpdateListener(timeInfo.currentTime, timeInfo.duration);
      }
    });
  }

  async setUrl(url: string): Promise<void> {
    if (!this.avPlayer || !this.isInitialized) {
      await this.init();
    }

    try {
      await this.avPlayer!.reset();
      await this.avPlayer!.setUrl(url);
      await this.avPlayer!.prepare();
    } catch (err) {
      const error = err as BusinessError;
      console.error(`PlayerService setUrl failed: ${error.code}, ${error.message}`);
      throw error;
    }
  }

  async play(): Promise<void> {
    if (!this.avPlayer) {
      return;
    }
    try {
      await this.avPlayer.play();
    } catch (err) {
      const error = err as BusinessError;
      console.error(`PlayerService play failed: ${error.code}, ${error.message}`);
      throw error;
    }
  }

  async pause(): Promise<void> {
    if (!this.avPlayer) {
      return;
    }
    try {
      await this.avPlayer.pause();
    } catch (err) {
      const error = err as BusinessError;
      console.error(`PlayerService pause failed: ${error.code}, ${error.message}`);
      throw error;
    }
  }

  async stop(): Promise<void> {
    if (!this.avPlayer) {
      return;
    }
    try {
      await this.avPlayer.stop();
    } catch (err) {
      const error = err as BusinessError;
      console.error(`PlayerService stop failed: ${error.code}, ${error.message}`);
      throw error;
    }
  }

  async seek(time: number): Promise<void> {
    if (!this.avPlayer) {
      return;
    }
    try {
      await this.avPlayer.seek(time, AVPlayer.SeekMode.PREV_SYNC);
    } catch (err) {
      const error = err as BusinessError;
      console.error(`PlayerService seek failed: ${error.code}, ${error.message}`);
      throw error;
    }
  }

  setVolume(volume: number): void {
    if (!this.avPlayer) {
      return;
    }
    this.avPlayer.setVolume(volume);
  }

  setStateChangeListener(listener: (state: AVPlayerState) => void): void {
    this.stateChangeListener = listener;
  }

  setTimeUpdateListener(listener: (time: number, duration: number) => void): void {
    this.timeUpdateListener = listener;
  }

  getCurrentState(): AVPlayerState | null {
    if (!this.avPlayer) {
      return null;
    }
    return this.avPlayer.state;
  }

  async release(): Promise<void> {
    if (!this.avPlayer) {
      return;
    }
    try {
      await this.avPlayer.release();
      this.avPlayer = null;
      this.isInitialized = false;
    } catch (err) {
      const error = err as BusinessError;
      console.error(`PlayerService release failed: ${error.code}, ${error.message}`);
      throw error;
    }
  }
}
