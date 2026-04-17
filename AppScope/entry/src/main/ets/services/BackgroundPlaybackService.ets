import { BusinessError } from '@kit.BasicServicesKit';
import { wantAgent } from '@kit.AbilityKit';
import type { common } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { avSession } from '@kit.AVSessionKit';
import type { MediaItem } from '../model/MediaItem';

export class BackgroundPlaybackService {
  private context: common.UIAbilityContext | null = null;
  private session: avSession.AVSession | null = null;
  private running: boolean = false;
  private sessionInitTask: Promise<void> | null = null;
  private backgroundStartTask: Promise<void> | null = null;
  private readonly sessionTag: string = 'PLAYER_SIRIUS_SESSION';

  setContext(context: common.UIAbilityContext): void {
    this.context = context;
  }

  async ensureStarted(currentItem: MediaItem, durationSeconds: number, positionSeconds: number, isPlaying: boolean): Promise<void> {
    if (!this.context) {
      return;
    }

    await this.ensureSession(currentItem, durationSeconds, positionSeconds, isPlaying);
    await this.startBackgroundTask();
  }

  async ensureStopped(): Promise<void> {
    await this.stopBackgroundTask();
    await this.destroySession();
  }

  async updateSessionState(currentItem: MediaItem, durationSeconds: number, positionSeconds: number, isPlaying: boolean): Promise<void> {
    if (!this.session) {
      return;
    }

    try {
      const metadata: avSession.AVMetadata = {
        assetId: currentItem.id,
        title: currentItem.title,
        duration: Math.max(0, Math.floor(durationSeconds * 1000)),
        description: currentItem.sourceType === 'network' ? '网络流' : '本地文件'
      };
      await this.session.setAVMetadata(metadata);

      const playbackState: avSession.AVPlaybackState = {
        state: isPlaying ? avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
        speed: 1.0,
        position: {
          elapsedTime: Math.max(0, Math.floor(positionSeconds * 1000)),
          updateTime: Date.now()
        }
      };
      await this.session.setAVPlaybackState(playbackState);
    } catch (err) {
      const error = err as BusinessError;
      console.error(`Update AVSession failed: ${error.code}, ${error.message}`);
    }
  }

  private async ensureSession(currentItem: MediaItem, durationSeconds: number, positionSeconds: number, isPlaying: boolean): Promise<void> {
    if (!this.context) {
      return;
    }
    if (this.session) {
      await this.updateSessionState(currentItem, durationSeconds, positionSeconds, isPlaying);
      return;
    }
    if (this.sessionInitTask) {
      await this.sessionInitTask;
      if (this.session) {
        await this.updateSessionState(currentItem, durationSeconds, positionSeconds, isPlaying);
      }
      return;
    }

    this.sessionInitTask = this.createAndActivateSession(currentItem, durationSeconds, positionSeconds, isPlaying);
    try {
      await this.sessionInitTask;
    } finally {
      this.sessionInitTask = null;
    }
  }

  private async createAndActivateSession(currentItem: MediaItem, durationSeconds: number, positionSeconds: number, isPlaying: boolean): Promise<void> {
    if (!this.context) {
      return;
    }
    try {
      this.session = await avSession.createAVSession(this.context, this.sessionTag, 'video');
      await this.session.activate();
      await this.updateSessionState(currentItem, durationSeconds, positionSeconds, isPlaying);
    } catch (err) {
      const error = err as BusinessError;
      console.error(`Create/activate AVSession failed: ${error.code}, ${error.message}`);
      this.session = null;
    }
  }

  private async destroySession(): Promise<void> {
    if (!this.session) {
      return;
    }
    try {
      await this.session.destroy();
    } catch {
      // ignore
    } finally {
      this.session = null;
    }
  }

  private async startBackgroundTask(): Promise<void> {
    if (!this.context || this.running) {
      return;
    }
    if (this.backgroundStartTask) {
      await this.backgroundStartTask;
      return;
    }
    this.backgroundStartTask = this.doStartBackgroundTask();
    try {
      await this.backgroundStartTask;
    } finally {
      this.backgroundStartTask = null;
    }
  }

  private async doStartBackgroundTask(): Promise<void> {
    if (!this.context) {
      return;
    }
    try {
      const wantAgentInfo: wantAgent.WantAgentInfo = {
        wants: [
          {
            bundleName: 'com.playersirius.app',
            abilityName: 'EntryAbility'
          }
        ],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const agent = await wantAgent.getWantAgent(wantAgentInfo);
      await backgroundTaskManager.startBackgroundRunning(
        this.context,
        backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK,
        agent
      );
      this.running = true;
    } catch (err) {
      const error = err as BusinessError;
      if (error.code === 9800005) {
        this.running = true;
        return;
      }
      console.error(`Start background running failed: ${error.code}, ${error.message}`);
      this.running = false;
    }
  }

  private async stopBackgroundTask(): Promise<void> {
    if (!this.context || !this.running) {
      return;
    }
    try {
      await backgroundTaskManager.stopBackgroundRunning(this.context);
    } catch {
      // ignore
    } finally {
      this.running = false;
    }
  }
}

