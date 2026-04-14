import { BusinessError } from '@kit.BasicServicesKit';
import { media } from '@kit.MediaKit';

export interface AVPlayerListener {
  onPrepared?: (durationSeconds: number) => void;
  onTimeUpdate?: (currentTimeSeconds: number) => void;
  onDurationUpdate?: (durationSeconds: number) => void;
  onStart?: () => void;
  onPause?: () => void;
  onCompletion?: () => void;
  onError?: (message: string) => void;
}

export class AVPlayerService {
  private avPlayer: media.AVPlayer | null = null;
  private listener: AVPlayerListener | null = null;
  private surfaceId: string = '';
  private callbacksRegistered: boolean = false;
  private autoPlayOnPrepared: boolean = true;
  private currentVolume: number = 1.0;
  private currentSpeed: number = 1.0;

  setListener(listener: AVPlayerListener): void {
    this.listener = listener;
  }

  async ensurePlayer(): Promise<media.AVPlayer> {
    if (!this.avPlayer) {
      this.avPlayer = await media.createAVPlayer();
      this.registerCallbacks(this.avPlayer);
    }
    return this.avPlayer;
  }

  async setSurfaceId(surfaceId: string): Promise<void> {
    this.surfaceId = surfaceId;
    if (!this.avPlayer || surfaceId.length === 0) {
      return;
    }

    try {
      this.avPlayer.surfaceId = surfaceId;
    } catch (err) {
      const error = err as BusinessError;
      console.error(`Set AVPlayer surface failed: ${error.code}, ${error.message}`);
    }
  }

  async open(url: string, autoPlay: boolean = true): Promise<void> {
    const player = await this.ensurePlayer();
    this.autoPlayOnPrepared = autoPlay;

    try {
      if (player.state !== 'idle') {
        await player.reset();
      }
      player.url = url;
    } catch (err) {
      const error = err as BusinessError;
      console.error(`Open AVPlayer source failed: ${error.code}, ${error.message}`);
      this.listener?.onError?.('AVPlayer 打开媒体失败。');
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
      console.error(`AVPlayer play failed: ${error.code}, ${error.message}`);
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
      console.error(`AVPlayer pause failed: ${error.code}, ${error.message}`);
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
      console.error(`AVPlayer stop failed: ${error.code}, ${error.message}`);
    }
  }

  async seek(seconds: number): Promise<void> {
    if (!this.avPlayer) {
      return;
    }

    try {
      await this.avPlayer.seek(Math.floor(seconds * 1000), media.SeekMode.SEEK_CLOSEST);
    } catch (err) {
      const error = err as BusinessError;
      console.error(`AVPlayer seek failed: ${error.code}, ${error.message}`);
    }
  }

  async setVolume(volume: number): Promise<void> {
    this.currentVolume = Math.max(0, Math.min(volume, 1));
    if (!this.avPlayer) {
      return;
    }
    await this.applyVolume(this.avPlayer);
  }

  async setSpeed(speed: number): Promise<void> {
    this.currentSpeed = speed;
    if (!this.avPlayer) {
      return;
    }
    await this.applySpeed(this.avPlayer);
  }

  async release(): Promise<void> {
    if (!this.avPlayer) {
      return;
    }

    try {
      await this.avPlayer.release();
    } catch (err) {
      const error = err as BusinessError;
      console.error(`AVPlayer release failed: ${error.code}, ${error.message}`);
    } finally {
      this.avPlayer = null;
      this.callbacksRegistered = false;
    }
  }

  private registerCallbacks(player: media.AVPlayer): void {
    if (this.callbacksRegistered) {
      return;
    }

    player.on('stateChange', async (state: string) => {
      try {
        if (!this.avPlayer) {
          return;
        }

        if (state === 'initialized') {
          if (this.surfaceId.length > 0) {
            this.avPlayer.surfaceId = this.surfaceId;
          }
          await this.avPlayer.prepare();
          return;
        }

        if (state === 'prepared') {
          await this.applyPlaybackSettings(this.avPlayer);
          const durationSeconds = Math.floor(this.avPlayer.duration / 1000);
          this.listener?.onPrepared?.(durationSeconds);
          this.listener?.onDurationUpdate?.(durationSeconds);
          if (this.autoPlayOnPrepared) {
            await this.avPlayer.play();
          }
          return;
        }

        if (state === 'playing') {
          this.listener?.onStart?.();
          return;
        }

        if (state === 'paused') {
          this.listener?.onPause?.();
          return;
        }

        if (state === 'completed') {
          this.listener?.onCompletion?.();
        }
      } catch (err) {
        const error = err as BusinessError;
        console.error(`AVPlayer state callback failed: ${error.code}, ${error.message}`);
        this.listener?.onError?.('AVPlayer 状态切换失败。');
      }
    });

    player.on('timeUpdate', (time: number) => {
      this.listener?.onTimeUpdate?.(Math.floor(time / 1000));
    });

    player.on('durationUpdate', (time: number) => {
      this.listener?.onDurationUpdate?.(Math.floor(time / 1000));
    });

    player.on('error', (err: BusinessError) => {
      console.error(`AVPlayer error: ${err.code}, ${err.message}`);
      this.listener?.onError?.('AVPlayer 播放失败。');
    });

    this.callbacksRegistered = true;
  }

  private async applyPlaybackSettings(player: media.AVPlayer): Promise<void> {
    await this.applyVolume(player);
    await this.applySpeed(player);
  }

  private async applyVolume(player: media.AVPlayer): Promise<void> {
    const volumeCapablePlayer = player as media.AVPlayer & {
      setVolume?: (volume: number) => Promise<void> | void;
    };
    if (!volumeCapablePlayer.setVolume) {
      return;
    }

    try {
      await volumeCapablePlayer.setVolume(this.currentVolume);
    } catch (err) {
      const error = err as BusinessError;
      console.error(`AVPlayer setVolume failed: ${error.code}, ${error.message}`);
    }
  }

  private async applySpeed(player: media.AVPlayer): Promise<void> {
    const speedCapablePlayer = player as media.AVPlayer & {
      setSpeed?: (speed: number) => Promise<void> | void;
    };
    if (!speedCapablePlayer.setSpeed) {
      return;
    }

    try {
      await speedCapablePlayer.setSpeed(this.currentSpeed);
    } catch (err) {
      const error = err as BusinessError;
      console.error(`AVPlayer setSpeed failed: ${error.code}, ${error.message}`);
    }
  }
}
