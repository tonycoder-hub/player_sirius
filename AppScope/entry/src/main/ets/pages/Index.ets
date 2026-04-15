import { picker } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import window from '@ohos.window';
import audio from '@ohos.multimedia.audio';
import type { AVPlayerListener, AVPlayerTrackSummary } from '../services/AVPlayerService';
import { PlayerService, PLAYBACK_SPEEDS } from '../services/PlayerService';
import { PlayerKernelService } from '../services/PlayerKernelService';
import { PermissionService } from '../services/PermissionService';
import { GlobalContext } from '../common/GlobalContext';
import type { MediaItem } from '../model/MediaItem';
import { MediaItemHelper } from '../model/MediaItem';
import type { SubtitleCue } from '../services/SubtitleService';
import { SubtitleService } from '../services/SubtitleService';
import type { WebDavEntry } from '../services/WebDavService';
import { WebDavService } from '../services/WebDavService';
import { WebDavDownloadService } from '../services/WebDavDownloadService';
import type { FtpEntry } from '../services/FtpService';
import { FtpService } from '../services/FtpService';
import type { DlnaDevice } from '../services/DlnaService';
import { DlnaService } from '../services/DlnaService';

const RESUME_THRESHOLD_SECONDS = 5;
const MAX_LIBRARY_IMPORT_COUNT = 30;
const ALL_FOLDERS_LABEL = '全部文件夹';

@Entry
@Component
struct Index {
  private videoController: VideoController = new VideoController();
  private xComponentController: XComponentController = new XComponentController();
  @State currentMediaItem: MediaItem | null = null;
  @State pendingOpenItem: MediaItem | null = null;
  @State isPlaying: boolean = false;
  @State currentSpeed: number = 1.0;
  @State currentTime: number = 0;
  @State duration: number = 0;
  @State isPrepared: boolean = false;
  @State isLoading: boolean = false;
  @State isDraggingProgress: boolean = false;
  @State hasMediaPermission: boolean = false;
  @State showPermissionGuide: boolean = false;
  @State hasPlayableError: boolean = false;
  @State isCompleted: boolean = false;
  @State showSpeedPicker: boolean = false;
  @State showPlaylist: boolean = false;
  @State showHistory: boolean = false;
  @State showLibrary: boolean = false;
  @State showResumePrompt: boolean = false;
  @State showNetworkInput: boolean = false;
  @State showMediaInfo: boolean = false;
  @State showTrackPanel: boolean = false;
  @State showRemotePanel: boolean = false;
  @State showCastingPanel: boolean = false;
  @State playlistItems: MediaItem[] = [];
  @State historyItems: MediaItem[] = [];
  @State libraryItems: MediaItem[] = [];
  @State favoriteItems: MediaItem[] = [];
  @State folderNames: string[] = [];
  @State activeLibraryTab: string = 'recent';
  @State selectedFolderName: string = ALL_FOLDERS_LABEL;
  @State networkUrl: string = '';
  @State errorMessage: string = '';
  @State libraryMessage: string = '';
  @State sessionPlayCountRecorded: boolean = false;
  @State isLandscapeMode: boolean = false;
  @State fitMode: string = 'contain';
  @State videoRotation: number = 0;
  @State playerVolume: number = 1.0;
  @State subtitleEnabled: boolean = false;
  @State subtitleOffsetSeconds: number = 0;
  @State subtitleUri: string = '';
  @State subtitleCues: SubtitleCue[] = [];
  @State subtitleText: string = '';
  @State subtitleMessage: string = '';
  @State audioTracks: AVPlayerTrackSummary[] = [];
  @State selectedAudioTrackIndex: number = -1;
  @State currentAudioTrack: string = '默认音轨';
  @State currentSubtitleLabel: string = '未加载';
  @State remoteMode: string = 'webdav';
  @State webDavBaseUrl: string = '';
  @State webDavUsername: string = '';
  @State webDavPassword: string = '';
  @State webDavPath: string = '/';
  @State webDavEntries: WebDavEntry[] = [];
  @State webDavMessage: string = '';
  @State webDavLoading: boolean = false;
  @State ftpHost: string = '';
  @State ftpPort: number = 21;
  @State ftpUsername: string = '';
  @State ftpPassword: string = '';
  @State ftpPath: string = '/';
  @State ftpEntries: FtpEntry[] = [];
  @State ftpMessage: string = '';
  @State ftpLoading: boolean = false;
  @State dlnaDevices: DlnaDevice[] = [];
  @State dlnaMessage: string = '';
  @State dlnaLoading: boolean = false;
  @State selectedDlnaDeviceUsn: string = '';
  @State gestureHint: string = '';
  @State playerKernelMode: string = 'video-component';
  @State avPlayerSurfaceId: string = '';
  @State videoSessionKey: number = 0;
  private playerService: PlayerService = GlobalContext.getPlayerService();
  private avPlayerService = GlobalContext.getAVPlayerService();
  private playerKernelService: PlayerKernelService = GlobalContext.getPlayerKernelService();
  private storageService = GlobalContext.getStorageService();
  private permissionService: PermissionService = new PermissionService();
  private backgroundPlaybackService = GlobalContext.getBackgroundPlaybackService();
  private lastSessionUpdateAt: number = 0;
  private wasPlayingBeforeInterrupt: boolean = false;
  private volumeBeforeDuck: number | null = null;

  aboutToAppear(): void {
    this.bindAVPlayerListeners();
    this.syncPlayerState();
    this.loadCollections();
  }

  aboutToDisappear(): void {
    this.persistCurrentItem();
    this.avPlayerService.release();
    this.backgroundPlaybackService.ensureStopped();
    this.setPreferredOrientation(window.Orientation.PORTRAIT);
  }

  private syncPlayerState(): void {
    this.currentMediaItem = this.playerService.getCurrentItem();
    this.currentSpeed = this.playerService.getSpeed();
    this.playerVolume = this.playerService.getVolume();
    this.avPlayerService.setSpeed(this.currentSpeed);
    this.avPlayerService.setVolume(this.playerVolume);
    this.updatePlaylist();
  }

  private async loadCollections(): Promise<void> {
    this.historyItems = await this.storageService.getPlayHistory();
    this.libraryItems = await this.storageService.getMediaLibrary();
    this.favoriteItems = this.libraryItems.filter((item: MediaItem) => item.isFavorite);
    this.folderNames = this.collectFolderNames(this.libraryItems);
    this.updateCurrentItemFromLibrary();
  }

  private collectFolderNames(items: MediaItem[]): string[] {
    const folderMap: Record<string, boolean> = {};
    items.forEach((item: MediaItem) => {
      if (item.folderName.length > 0) {
        folderMap[item.folderName] = true;
      }
    });

    const names = Object.keys(folderMap).sort((left: string, right: string) => left.localeCompare(right));
    return [ALL_FOLDERS_LABEL, ...names];
  }

  private updateCurrentItemFromLibrary(): void {
    if (!this.currentMediaItem) {
      return;
    }

    const merged = this.findExistingMedia(this.currentMediaItem.uri);
    if (merged) {
      Object.assign(this.currentMediaItem, merged, {
        lastPosition: this.currentTime,
        duration: this.duration > 0 ? this.duration : merged.duration
      });
    }
  }

  private getUiContext(): common.UIAbilityContext {
    return getContext(this) as common.UIAbilityContext;
  }

  private getObjectFitMode(): ImageFit {
    return this.fitMode === 'cover' ? ImageFit.Cover : ImageFit.Contain;
  }

  private supportsPreciseVolumeControl(): boolean {
    return this.isUsingAVPlayer();
  }

  private getVolumeDisplayText(): string {
    if (this.supportsPreciseVolumeControl()) {
      return `${Math.round(this.playerVolume * 100)}%`;
    }
    return this.playerVolume <= 0 ? '静音' : '跟随系统';
  }

  private getVolumeDownLabel(): string {
    return this.supportsPreciseVolumeControl() ? '-音量' : '静音';
  }

  private getVolumeUpLabel(): string {
    return this.supportsPreciseVolumeControl() ? '+音量' : '开声';
  }

  private supportsSubtitleFeature(): boolean {
    return this.playerKernelService.supportsFeatureByMode(this.playerKernelMode, 'externalSubtitle');
  }

  private supportsSubtitleOffsetFeature(): boolean {
    return this.playerKernelService.supportsFeatureByMode(this.playerKernelMode, 'subtitleOffset');
  }

  private supportsAudioTrackFeature(): boolean {
    return this.playerKernelService.supportsFeatureByMode(this.playerKernelMode, 'multiAudioTrack');
  }

  private getTrackPanelHint(): string {
    if (this.supportsAudioTrackFeature()) {
      return '当前内核支持真实多音轨切换。';
    }
    return '当前版本仅预留字幕/音轨入口，真实切换尚未接入 AVPlayer 或 Native 内核。';
  }

  private isUsingAVPlayer(): boolean {
    return this.playerKernelMode === 'avplayer-native';
  }

  private bindAVPlayerListeners(): void {
    const listener: AVPlayerListener = {
      onPrepared: (durationSeconds: number) => {
        this.duration = durationSeconds;
        this.isPrepared = true;
        this.isLoading = false;
        if (this.currentMediaItem) {
          this.currentMediaItem.duration = durationSeconds;
          this.currentMediaItem.isCompleted = false;
        }
        if (this.currentTime > 0) {
          this.avPlayerService.seek(this.currentTime);
        }
        this.updateSubtitleRender(this.currentTime);
        this.refreshAudioTracks();
        this.maybeUpdateBackgroundSession();
      },
      onTimeUpdate: (currentTimeSeconds: number) => {
        if (!this.isDraggingProgress) {
          this.currentTime = currentTimeSeconds;
          this.syncCurrentItemProgress();
          this.updateSubtitleRender(currentTimeSeconds);
          this.maybeUpdateBackgroundSession();
        }
      },
      onDurationUpdate: (durationSeconds: number) => {
        this.duration = durationSeconds;
      },
      onStart: () => {
        this.isPlaying = true;
        this.isLoading = false;
        this.markCurrentPlaySession();
        this.startBackgroundPlaybackIfNeeded();
      },
      onPause: () => {
        this.isPlaying = false;
        this.persistCurrentItem();
        this.backgroundPlaybackService.ensureStopped();
      },
      onCompletion: () => {
        this.isPlaying = false;
        this.isCompleted = true;
        this.currentTime = 0;
        this.updateSubtitleRender(0);
        this.backgroundPlaybackService.ensureStopped();
        if (this.currentMediaItem) {
          this.currentMediaItem.lastPosition = 0;
          this.currentMediaItem.isCompleted = true;
          this.currentMediaItem.lastPlayedAt = Date.now();
        }
        this.persistCurrentItem();
      },
      onError: (message: string) => {
        this.handlePlaybackFailure(message);
        this.backgroundPlaybackService.ensureStopped();
      },
      onAudioInterrupt: (event: unknown) => {
        this.handleAudioInterrupt(event);
      }
    };
    this.avPlayerService.setListener(listener);
  }

  private handleAudioInterrupt(event: unknown): void {
    // Refer to Audio focus guide: interruptEvent.forceType + interruptEvent.hintType. Keep logic tolerant to API variations.
    const interruptEvent = event as unknown as {
      forceType?: number;
      hintType?: number;
    };
    const hintType = interruptEvent?.hintType;

    if (hintType === audio.InterruptHint.INTERRUPT_HINT_PAUSE) {
      this.wasPlayingBeforeInterrupt = this.isPlaying;
      if (this.isPlaying) {
        this.avPlayerService.pause();
        this.isPlaying = false;
        this.gestureHint = '音频被系统打断：已暂停';
      }
      this.backgroundPlaybackService.ensureStopped();
      return;
    }

    if (hintType === audio.InterruptHint.INTERRUPT_HINT_RESUME) {
      if (this.wasPlayingBeforeInterrupt && this.isPrepared && !this.hasPlayableError) {
        this.avPlayerService.play();
        this.isPlaying = true;
        this.gestureHint = '音频焦点已恢复：继续播放';
        this.startBackgroundPlaybackIfNeeded();
      }
      this.wasPlayingBeforeInterrupt = false;
      return;
    }

    if (hintType === audio.InterruptHint.INTERRUPT_HINT_STOP) {
      this.wasPlayingBeforeInterrupt = false;
      this.avPlayerService.stop();
      this.isPlaying = false;
      this.gestureHint = '音频被系统打断：已停止';
      this.backgroundPlaybackService.ensureStopped();
      return;
    }

    if (hintType === audio.InterruptHint.INTERRUPT_HINT_DUCK) {
      // Reduce volume temporarily, only when AVPlayer supports precise volume.
      if (this.supportsPreciseVolumeControl() && this.volumeBeforeDuck === null) {
        this.volumeBeforeDuck = this.playerVolume;
        const ducked = Math.max(0, Math.min(this.playerVolume * 0.2, 1));
        this.playerVolume = ducked;
        this.playerService.setVolume(ducked);
        this.avPlayerService.setVolume(ducked);
        this.gestureHint = '音频焦点变化：已降低音量';
      }
      return;
    }

    if (hintType === audio.InterruptHint.INTERRUPT_HINT_UNDUCK) {
      if (this.supportsPreciseVolumeControl() && this.volumeBeforeDuck !== null) {
        const restored = this.volumeBeforeDuck;
        this.volumeBeforeDuck = null;
        this.playerVolume = restored;
        this.playerService.setVolume(restored);
        this.avPlayerService.setVolume(restored);
        this.gestureHint = '音频焦点变化：已恢复音量';
      }
    }
  }

  private startBackgroundPlaybackIfNeeded(): void {
    if (!this.currentMediaItem) {
      return;
    }
    // Only start when actually playing, otherwise the system may cancel the task.
    this.backgroundPlaybackService.ensureStarted(this.currentMediaItem, this.duration, this.currentTime, true);
  }

  private maybeUpdateBackgroundSession(): void {
    if (!this.currentMediaItem) {
      return;
    }
    const now = Date.now();
    if (now - this.lastSessionUpdateAt < 2000) {
      return;
    }
    this.lastSessionUpdateAt = now;
    this.backgroundPlaybackService.updateSessionState(
      this.currentMediaItem,
      this.duration,
      this.currentTime,
      this.isPlaying
    );
  }

  private async listWebDavDirectory(): Promise<void> {
    const baseUrl = this.webDavBaseUrl.trim();
    if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
      this.webDavMessage = '请输入有效的 WebDAV 地址（http/https）。';
      return;
    }
    this.webDavLoading = true;
    this.webDavMessage = '正在读取目录...';
    try {
      const entries = await WebDavService.listDirectory(
        baseUrl,
        this.webDavPath,
        this.webDavUsername.trim(),
        this.webDavPassword
      );
      this.webDavEntries = entries;
      this.webDavMessage = entries.length > 0 ? `已读取 ${entries.length} 项` : '目录为空或无权限。';
    } catch (err) {
      console.error(`WebDAV list failed: ${err}`);
      this.webDavEntries = [];
      this.webDavMessage = (err as Error)?.message || 'WebDAV 列目录失败。';
    } finally {
      this.webDavLoading = false;
    }
  }

  private async listFtpDirectory(): Promise<void> {
    const host = this.ftpHost.trim();
    if (host.length === 0) {
      this.ftpMessage = '请输入 FTP 主机地址。';
      return;
    }
    const port = Number(this.ftpPort) || 21;
    this.ftpLoading = true;
    this.ftpMessage = '正在读取目录...';
    try {
      const entries = await FtpService.listDirectory(
        host,
        port,
        this.ftpUsername.trim(),
        this.ftpPassword,
        this.ftpPath
      );
      this.ftpEntries = entries;
      this.ftpMessage = entries.length > 0 ? `已读取 ${entries.length} 项` : '目录为空或无权限。';
    } catch (err) {
      console.error(`FTP list failed: ${err}`);
      this.ftpEntries = [];
      this.ftpMessage = (err as Error)?.message || 'FTP 列目录失败。';
    } finally {
      this.ftpLoading = false;
    }
  }

  private async openFtpEntry(entry: FtpEntry): Promise<void> {
    if (entry.isDirectory) {
      this.ftpPath = entry.path;
      await this.listFtpDirectory();
      return;
    }

    try {
      const ctx = this.getUiContext();
      this.ftpMessage = '正在下载到缓存...';
      const localUri = await FtpService.downloadToCache(
        ctx,
        this.ftpHost.trim(),
        Number(this.ftpPort) || 21,
        this.ftpUsername.trim(),
        this.ftpPassword,
        entry.path,
        entry.name
      );
      this.showRemotePanel = false;
      const item = this.createPlayableItem(localUri, entry.name);
      item.folderName = 'FTP 缓存';
      item.sourceType = 'local';
      await this.storageService.upsertMediaItem(item);
      await this.loadCollections();
      await this.requestOpenItem(item);
    } catch (err) {
      console.error(`FTP download failed: ${err}`);
      this.ftpMessage = (err as Error)?.message || 'FTP 下载失败';
    }
  }

  private getSelectedDlnaDevice(): DlnaDevice | null {
    return this.dlnaDevices.find((device: DlnaDevice) => device.usn === this.selectedDlnaDeviceUsn) ?? null;
  }

  private getCurrentCastableUrl(): string {
    if (!this.currentMediaItem) {
      return '';
    }
    const uri = this.currentMediaItem.uri.trim();
    if (uri.startsWith('http://') || uri.startsWith('https://')) {
      return uri;
    }
    return '';
  }

  private async discoverDlnaDevices(): Promise<void> {
    this.dlnaLoading = true;
    this.dlnaMessage = '正在搜索设备...';
    try {
      const devices = await DlnaService.discoverDevices(3000);
      this.dlnaDevices = devices;
      if (devices.length > 0) {
        this.selectedDlnaDeviceUsn = devices[0].usn;
      } else {
        this.selectedDlnaDeviceUsn = '';
      }
      this.dlnaMessage = devices.length > 0 ? `已发现 ${devices.length} 台设备` : '未发现 DLNA 设备';
    } catch (err) {
      console.error(`DLNA discover failed: ${err}`);
      this.dlnaDevices = [];
      this.selectedDlnaDeviceUsn = '';
      this.dlnaMessage = (err as Error)?.message || '设备发现失败';
    } finally {
      this.dlnaLoading = false;
    }
  }

  private async castToSelectedDevice(): Promise<void> {
    const device = this.getSelectedDlnaDevice();
    const mediaUrl = this.getCurrentCastableUrl();
    if (!device) {
      this.dlnaMessage = '请先选择设备';
      return;
    }
    if (mediaUrl.length === 0) {
      this.dlnaMessage = '当前仅支持投送 HTTP/HTTPS 网络流，本地文件暂未转 HTTP 服务';
      return;
    }
    this.dlnaMessage = '正在投送媒体...';
    try {
      await DlnaService.cast(device, mediaUrl);
      this.dlnaMessage = `已投送到 ${device.friendlyName}`;
    } catch (err) {
      console.error(`DLNA cast failed: ${err}`);
      this.dlnaMessage = (err as Error)?.message || '投送失败';
    }
  }

  private async playOnSelectedDevice(): Promise<void> {
    const device = this.getSelectedDlnaDevice();
    if (!device) {
      this.dlnaMessage = '请先选择设备';
      return;
    }
    try {
      await DlnaService.play(device);
      this.dlnaMessage = `已让 ${device.friendlyName} 播放`;
    } catch (err) {
      this.dlnaMessage = (err as Error)?.message || '播放控制失败';
    }
  }

  private async pauseOnSelectedDevice(): Promise<void> {
    const device = this.getSelectedDlnaDevice();
    if (!device) {
      this.dlnaMessage = '请先选择设备';
      return;
    }
    try {
      await DlnaService.pause(device);
      this.dlnaMessage = `已让 ${device.friendlyName} 暂停`;
    } catch (err) {
      this.dlnaMessage = (err as Error)?.message || '暂停控制失败';
    }
  }

  private async stopOnSelectedDevice(): Promise<void> {
    const device = this.getSelectedDlnaDevice();
    if (!device) {
      this.dlnaMessage = '请先选择设备';
      return;
    }
    try {
      await DlnaService.stop(device);
      this.dlnaMessage = `已让 ${device.friendlyName} 停止`;
    } catch (err) {
      this.dlnaMessage = (err as Error)?.message || '停止控制失败';
    }
  }

  private setWebDavPathFromHref(href: string): void {
    try {
      const base = new URL(this.webDavBaseUrl.trim());
      const entry = new URL(href);
      const basePath = base.pathname.replace(/\/+$/, '');
      const entryPath = entry.pathname;
      let relative = entryPath.startsWith(basePath) ? entryPath.slice(basePath.length) : entryPath;
      if (relative.length === 0) {
        relative = '/';
      }
      if (!relative.startsWith('/')) {
        relative = `/${relative}`;
      }
      this.webDavPath = relative;
    } catch {
      // Fallback: keep current path.
    }
  }

  private async openWebDavEntry(entry: WebDavEntry): Promise<void> {
    if (entry.isDirectory) {
      this.setWebDavPathFromHref(entry.href);
      await this.listWebDavDirectory();
      return;
    }

    // If credentials exist, download into sandbox cache first to make playback work without custom headers.
    if (this.webDavUsername.trim().length > 0) {
      try {
        const ctx = this.getUiContext();
        this.webDavMessage = '正在下载到缓存...';
        const localUri = await WebDavDownloadService.downloadToCache(
          ctx,
          entry.href,
          entry.name,
          this.webDavUsername.trim(),
          this.webDavPassword
        );
        this.showRemotePanel = false;
        const item = this.createPlayableItem(localUri, entry.name);
        item.folderName = 'WebDAV 缓存';
        item.sourceType = 'local';
        await this.storageService.upsertMediaItem(item);
        await this.loadCollections();
        await this.requestOpenItem(item);
        return;
      } catch (err) {
        console.error(`WebDAV download failed: ${err}`);
        this.webDavMessage = (err as Error)?.message || '下载失败';
        return;
      }
    }

    // Otherwise, try to open with direct URL. If the WebDAV server requires auth headers, playback may fail.
    this.showRemotePanel = false;
    this.networkUrl = entry.href;
    await this.openNetworkMedia();
  }

  private async setPreferredOrientation(orientation: window.Orientation): Promise<void> {
    try {
      const mainWindow = this.getUiContext().windowStage.getMainWindowSync();
      await mainWindow.setPreferredOrientation(orientation);
    } catch (err) {
      const error = err as BusinessError;
      console.error(`Set orientation failed: ${error.code}, ${error.message}`);
    }
  }

  private async toggleOrientation(): Promise<void> {
    this.isLandscapeMode = !this.isLandscapeMode;
    await this.setPreferredOrientation(
      this.isLandscapeMode ? window.Orientation.LANDSCAPE : window.Orientation.PORTRAIT
    );
  }

  private cycleFitMode(): void {
    this.fitMode = this.fitMode === 'contain' ? 'cover' : 'contain';
  }

  private rotateVideo(): void {
    this.videoRotation = (this.videoRotation + 90) % 360;
  }

  private adjustVolume(delta: number): void {
    const nextVolume = this.supportsPreciseVolumeControl()
      ? Math.max(0, Math.min(this.playerVolume + delta, 1))
      : (delta < 0 ? 0 : 1);
    this.playerVolume = nextVolume;
    this.playerService.setVolume(nextVolume);
    this.avPlayerService.setVolume(nextVolume);
    this.gestureHint = this.supportsPreciseVolumeControl()
      ? `音量 ${Math.round(nextVolume * 100)}%`
      : (nextVolume <= 0 ? '已静音' : '已恢复音频输出');
  }

  private adjustProgress(delta: number): void {
    const nextTime = Math.max(0, Math.min(this.currentTime + delta, this.duration > 0 ? this.duration : 0));
    this.currentTime = nextTime;
    if (this.isPrepared) {
      if (this.isUsingAVPlayer()) {
        this.avPlayerService.seek(nextTime);
      } else {
        this.videoController.setCurrentTime(nextTime, SeekMode.Accurate);
      }
    }
    this.gestureHint = `进度 ${this.formatTime(nextTime)}`;
    this.updateSubtitleRender(nextTime);
    this.maybeUpdateBackgroundSession();
  }

  private adjustSubtitleOffset(delta: number): void {
    if (!this.supportsSubtitleOffsetFeature()) {
      this.gestureHint = '字幕偏移尚未实现';
      return;
    }
    this.subtitleOffsetSeconds = Math.max(-10, Math.min(this.subtitleOffsetSeconds + delta, 10));
    this.updateSubtitleRender(this.currentTime);
  }

  private toggleSubtitle(): void {
    if (!this.supportsSubtitleFeature()) {
      this.subtitleEnabled = false;
      this.currentSubtitleLabel = '未加载';
      this.gestureHint = '外挂字幕尚未实现';
      return;
    }
    if (this.subtitleCues.length === 0) {
      this.subtitleEnabled = false;
      this.currentSubtitleLabel = '未加载';
      this.gestureHint = '请先选择字幕文件（.srt）';
      return;
    }
    this.subtitleEnabled = !this.subtitleEnabled;
    this.currentSubtitleLabel = this.subtitleEnabled ? '已启用' : '已关闭';
    this.updateSubtitleRender(this.currentTime);
  }

  private getSubtitleFileName(): string {
    if (this.subtitleUri.length === 0) {
      return '未选择';
    }
    const segments = this.subtitleUri.split('/');
    return segments.length > 0 ? segments[segments.length - 1] : this.subtitleUri;
  }

  private async pickSubtitleFile(): Promise<void> {
    try {
      const context = this.getUiContext();
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['字幕文件(.srt)|.srt', '所有文件(*.*)|.*'];
      const documentPicker = new picker.DocumentViewPicker(context);
      const result = await documentPicker.select(options);
      if (!result || result.length === 0) {
        return;
      }
      await this.loadSubtitleFromUri(result[0]);
    } catch (err) {
      const error = err as BusinessError;
      console.error(`Pick subtitle failed: ${error.code}, ${error.message}`);
      this.subtitleMessage = '选择字幕失败，请稍后重试。';
    }
  }

  private clearSubtitle(): void {
    this.subtitleUri = '';
    this.subtitleCues = [];
    this.subtitleText = '';
    this.subtitleEnabled = false;
    this.currentSubtitleLabel = '未加载';
    this.subtitleMessage = '';
  }

  private async loadSubtitleFromUri(uri: string): Promise<void> {
    this.subtitleMessage = '正在加载字幕...';
    this.subtitleUri = uri;
    this.subtitleText = '';
    this.subtitleEnabled = false;
    this.currentSubtitleLabel = '未加载';

    try {
      const content = await SubtitleService.readTextFromUri(uri);
      const cues = SubtitleService.parseSrt(content);
      this.subtitleCues = cues;
      this.subtitleEnabled = cues.length > 0;
      this.currentSubtitleLabel = cues.length > 0 ? '已启用' : '无有效字幕';
      this.subtitleMessage = cues.length > 0 ? `已加载 ${cues.length} 条字幕` : '字幕文件解析成功，但未找到有效字幕条目。';
      this.updateSubtitleRender(this.currentTime);
    } catch (err) {
      console.error(`Load subtitle failed: ${err}`);
      this.subtitleCues = [];
      this.subtitleEnabled = false;
      this.currentSubtitleLabel = '加载失败';
      this.subtitleMessage = (err as Error)?.message || '字幕加载失败。';
    }
  }

  private resetAudioTracks(): void {
    this.audioTracks = [];
    this.selectedAudioTrackIndex = -1;
    this.currentAudioTrack = '默认音轨';
  }

  private async refreshAudioTracks(): Promise<void> {
    if (!this.isUsingAVPlayer() || !this.supportsAudioTrackFeature()) {
      this.resetAudioTracks();
      return;
    }

    try {
      const tracks = await this.avPlayerService.getAudioTracks();
      this.audioTracks = tracks;
      if (this.selectedAudioTrackIndex >= 0) {
        const stillExists = tracks.some((t: AVPlayerTrackSummary) => t.trackIndex === this.selectedAudioTrackIndex);
        if (!stillExists) {
          this.selectedAudioTrackIndex = -1;
          this.currentAudioTrack = '默认音轨';
        }
      }
      if (tracks.length === 0) {
        this.currentAudioTrack = '无可枚举音轨';
      }
    } catch (err) {
      console.error(`Refresh audio tracks failed: ${err}`);
      this.audioTracks = [];
      this.currentAudioTrack = '音轨枚举失败';
    }
  }

  private updateSubtitleRender(currentTimeSeconds: number): void {
    if (!this.subtitleEnabled || this.subtitleCues.length === 0) {
      this.subtitleText = '';
      return;
    }
    // Positive offset means subtitles show later, so we query "earlier" cues at (t - offset).
    const adjustedMs = Math.floor((currentTimeSeconds - this.subtitleOffsetSeconds) * 1000);
    const cue = SubtitleService.findCueAt(this.subtitleCues, adjustedMs);
    this.subtitleText = cue ? cue.text : '';
  }

  private selectAudioTrack(trackName: string): void {
    if (!this.supportsAudioTrackFeature()) {
      this.gestureHint = '多音轨切换尚未实现';
      return;
    }
    this.currentAudioTrack = trackName;
    this.gestureHint = `已切换到 ${trackName}`;
  }

  private async selectAudioTrackByIndex(trackIndex: number): Promise<void> {
    if (!this.supportsAudioTrackFeature() || !this.isUsingAVPlayer()) {
      this.gestureHint = '当前内核不支持音轨切换';
      return;
    }

    try {
      if (trackIndex < 0) {
        if (this.selectedAudioTrackIndex >= 0) {
          await this.avPlayerService.deselectTrack(this.selectedAudioTrackIndex);
        }
        this.selectedAudioTrackIndex = -1;
        this.currentAudioTrack = '默认音轨';
        this.gestureHint = '已恢复默认音轨';
        return;
      }

      await this.avPlayerService.selectTrack(trackIndex);
      const selected = this.audioTracks.find((t: AVPlayerTrackSummary) => t.trackIndex === trackIndex);
      this.selectedAudioTrackIndex = trackIndex;
      this.currentAudioTrack = selected?.label ?? `音轨 ${trackIndex}`;
      this.gestureHint = `已切换到 ${this.currentAudioTrack}`;
    } catch (err) {
      console.error(`Select audio track failed: ${err}`);
      this.gestureHint = '音轨切换失败';
    }
  }

  private async switchKernel(mode: string): Promise<void> {
    if (this.playerKernelMode === mode) {
      return;
    }

    this.persistCurrentItem();
    if (this.isUsingAVPlayer()) {
      await this.avPlayerService.stop();
    }
    this.playerKernelMode = mode;
    this.resetPlaybackFlags();
    this.resetAudioTracks();
    this.gestureHint = `已切换到 ${this.playerKernelService.getKernelByMode(mode).displayName}`;

    if (this.currentMediaItem && this.isUsingAVPlayer() && this.avPlayerSurfaceId.length > 0) {
      this.isLoading = true;
      await this.avPlayerService.setSurfaceId(this.avPlayerSurfaceId);
      await this.avPlayerService.open(this.currentMediaItem.uri, true);
    }
  }

  private async onAVPlayerSurfaceLoad(): Promise<void> {
    this.avPlayerSurfaceId = this.xComponentController.getXComponentSurfaceId();
    await this.avPlayerService.setSurfaceId(this.avPlayerSurfaceId);
    if (this.currentMediaItem && this.isUsingAVPlayer() && !this.isPrepared) {
      this.isLoading = true;
      await this.avPlayerService.open(this.currentMediaItem.uri, true);
    }
  }

  private async ensureMediaPermission(openSettingIfDenied: boolean = false): Promise<boolean> {
    const context = this.getUiContext();
    const granted = await this.permissionService.requestPermission(context, 'ohos.permission.READ_MEDIA');
    this.hasMediaPermission = granted;
    this.showPermissionGuide = !granted;
    if (!granted && openSettingIfDenied) {
      const settingGranted = await this.permissionService.openPermissionSetting(context, 'ohos.permission.READ_MEDIA');
      this.hasMediaPermission = settingGranted;
      this.showPermissionGuide = !settingGranted;
      return settingGranted;
    }
    return granted;
  }

  private resetPlaybackFlags(): void {
    this.isPrepared = false;
    this.isLoading = true;
    this.isPlaying = false;
    this.hasPlayableError = false;
    this.isCompleted = false;
    this.errorMessage = '';
    this.sessionPlayCountRecorded = false;
  }

  private stopCurrentPlaybackForSwitch(): void {
    if (this.isUsingAVPlayer()) {
      this.avPlayerService.stop();
    } else if (this.currentMediaItem && this.isPrepared) {
      this.videoController.stop();
    }
    this.backgroundPlaybackService.ensureStopped();
    this.isPlaying = false;
    this.isPrepared = false;
    this.isLoading = false;
  }

  private handlePlaybackFailure(message: string): void {
    this.isPrepared = false;
    this.isLoading = false;
    this.isPlaying = false;
    this.hasPlayableError = true;
    this.errorMessage = message;
    this.backgroundPlaybackService.ensureStopped();
  }

  private getSelectVideoErrorMessage(error: BusinessError): string {
    if (error.code === 13900042) {
      return '没有可访问的视频文件，请确认媒体库中存在视频。';
    }
    if (error.code === 201 || error.code === 202) {
      return '';
    }
    return '选择视频失败，请稍后重试。';
  }

  private findExistingMedia(uri: string): MediaItem | null {
    const libraryMatch = this.libraryItems.find((item: MediaItem) => item.uri === uri);
    if (libraryMatch) {
      return { ...libraryMatch };
    }

    const historyMatch = this.historyItems.find((item: MediaItem) => item.uri === uri);
    if (historyMatch) {
      return { ...historyMatch };
    }

    return null;
  }

  private createPlayableItem(uri: string, title?: string): MediaItem {
    const existing = this.findExistingMedia(uri);
    if (existing) {
      return {
        ...existing,
        title: title && title.length > 0 ? title : existing.title,
        sourceType: MediaItemHelper.isNetworkUri(uri) ? 'network' : existing.sourceType,
        folderName: MediaItemHelper.isNetworkUri(uri) ? '网络流' : existing.folderName
      };
    }

    const displayTitle = title && title.length > 0 ? title : MediaItemHelper.getDisplayTitle(uri);
    return MediaItemHelper.createWithOptions(uri, displayTitle, {
      sourceType: MediaItemHelper.isNetworkUri(uri) ? 'network' : 'local',
      folderName: MediaItemHelper.isNetworkUri(uri) ? '网络流' : MediaItemHelper.getFolderName(uri)
    });
  }

  private shouldPromptResume(item: MediaItem): boolean {
    return item.duration > 0
      && item.lastPosition >= RESUME_THRESHOLD_SECONDS
      && item.lastPosition < item.duration - RESUME_THRESHOLD_SECONDS
      && !item.isCompleted;
  }

  private async requestOpenItem(item: MediaItem): Promise<void> {
    this.persistCurrentItem();
    this.stopCurrentPlaybackForSwitch();

    if (this.shouldPromptResume(item)) {
      this.pendingOpenItem = { ...item };
      this.showResumePrompt = true;
      return;
    }

    await this.applyOpenItem(item, true);
  }

  private async applyOpenItem(item: MediaItem, resumeFromHistory: boolean): Promise<void> {
    const playable = this.playerService.addOrActivate({
      ...item,
      lastPosition: resumeFromHistory ? item.lastPosition : 0,
      isCompleted: false,
      lastPlayedAt: Date.now()
    });
    this.currentMediaItem = playable;
    this.currentTime = playable.lastPosition;
    this.duration = playable.duration;
    this.networkUrl = playable.sourceType === 'network' ? playable.uri : this.networkUrl;
    this.pendingOpenItem = null;
    this.showResumePrompt = false;
    this.resetPlaybackFlags();
    this.clearSubtitle();
    this.resetAudioTracks();
    await this.storageService.savePlayHistory(playable);
    this.updatePlaylist();
    await this.loadCollections();
    if (this.isUsingAVPlayer() && this.avPlayerSurfaceId.length > 0) {
      this.isLoading = true;
      await this.avPlayerService.setSurfaceId(this.avPlayerSurfaceId);
      await this.avPlayerService.open(playable.uri, true);
    } else if (!this.isUsingAVPlayer()) {
      this.videoSessionKey++;
    }
  }

  private async confirmResumePlayback(resumeFromHistory: boolean): Promise<void> {
    if (!this.pendingOpenItem) {
      return;
    }
    await this.applyOpenItem(this.pendingOpenItem, resumeFromHistory);
  }

  private getFileNameFromUri(uri: string): string {
    return MediaItemHelper.getDisplayTitle(uri);
  }

  private async selectVideo(): Promise<void> {
    try {
      const permissionGranted = await this.ensureMediaPermission();
      if (!permissionGranted) {
        this.handlePlaybackFailure('需要媒体访问权限后才能选择并播放本地视频。');
        return;
      }

      const photoPicker = new picker.PhotoViewPicker();
      const result = await photoPicker.select({
        MIMEType: picker.PhotoViewMIMETypes.VIDEO_TYPE,
        maxSelectNumber: 1
      });

      if (result.photoUris && result.photoUris.length > 0) {
        const uri = result.photoUris[0];
        const item = this.createPlayableItem(uri, this.getFileNameFromUri(uri));
        await this.storageService.upsertMediaItem(item);
        await this.loadCollections();
        await this.requestOpenItem(item);
      }
    } catch (err) {
      const error = err as BusinessError;
      console.error(`Select video failed: ${error.code}, ${error.message}`);
      const message = this.getSelectVideoErrorMessage(error);
      if (message.length > 0) {
        this.handlePlaybackFailure(message);
      }
    }
  }

  private async importMediaLibrary(): Promise<void> {
    try {
      const permissionGranted = await this.ensureMediaPermission();
      if (!permissionGranted) {
        this.libraryMessage = '需要先授权媒体访问权限后才能导入本地媒体。';
        return;
      }

      const photoPicker = new picker.PhotoViewPicker();
      const result = await photoPicker.select({
        MIMEType: picker.PhotoViewMIMETypes.VIDEO_TYPE,
        maxSelectNumber: MAX_LIBRARY_IMPORT_COUNT
      });

      const uris = result.photoUris ?? [];
      if (uris.length === 0) {
        return;
      }

      const items = uris.map((uri: string) => this.createPlayableItem(uri, this.getFileNameFromUri(uri)));
      await this.storageService.saveMediaLibraryItems(items);
      this.libraryMessage = `已导入 ${items.length} 个本地媒体，可在媒体库和文件夹视图中浏览。`;
      await this.loadCollections();
      this.activeLibraryTab = 'library';
      this.showLibrary = true;
    } catch (err) {
      const error = err as BusinessError;
      console.error(`Import media library failed: ${error.code}, ${error.message}`);
      this.libraryMessage = this.getSelectVideoErrorMessage(error) || '导入本地媒体失败，请稍后重试。';
    }
  }

  private async openNetworkMedia(): Promise<void> {
    const url = this.networkUrl.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      this.handlePlaybackFailure('请输入有效的 HTTP/HTTPS 地址，HLS 请输入 m3u8 直链。');
      return;
    }

    const item = this.createPlayableItem(url, MediaItemHelper.getDisplayTitle(url));
    item.sourceType = 'network';
    item.folderName = '网络流';
    await this.storageService.upsertMediaItem(item);
    await this.loadCollections();
    await this.requestOpenItem(item);
  }

  private async openFromHistory(item: MediaItem): Promise<void> {
    this.showHistory = false;
    await this.requestOpenItem(item);
  }

  private async openFromLibrary(item: MediaItem): Promise<void> {
    this.showLibrary = false;
    await this.requestOpenItem(item);
  }

  private async activatePlaylistItem(item: MediaItem | null): Promise<void> {
    if (!item) {
      this.updatePlaylist();
      return;
    }

    this.currentMediaItem = item;
    this.currentTime = item.lastPosition;
    this.duration = item.duration;
    this.networkUrl = item.sourceType === 'network' ? item.uri : this.networkUrl;
    this.resetPlaybackFlags();
    this.clearSubtitle();
    this.resetAudioTracks();
    await this.storageService.savePlayHistory(item);
    this.updatePlaylist();
    await this.loadCollections();
    if (this.isUsingAVPlayer() && this.avPlayerSurfaceId.length > 0) {
      this.isLoading = true;
      await this.avPlayerService.setSurfaceId(this.avPlayerSurfaceId);
      await this.avPlayerService.open(item.uri, true);
    } else if (!this.isUsingAVPlayer()) {
      this.videoSessionKey++;
    }
  }

  private async playFromPlaylist(index: number): Promise<void> {
    this.persistCurrentItem();
    this.stopCurrentPlaybackForSwitch();
    const item = this.playerService.selectByIndex(index);
    await this.activatePlaylistItem(item);
    this.showPlaylist = false;
  }

  private async playNext(): Promise<void> {
    this.persistCurrentItem();
    this.stopCurrentPlaybackForSwitch();
    await this.activatePlaylistItem(this.playerService.playNext());
  }

  private async playPrevious(): Promise<void> {
    this.persistCurrentItem();
    this.stopCurrentPlaybackForSwitch();
    await this.activatePlaylistItem(this.playerService.playPrevious());
  }

  private changeSpeed(speed: number): void {
    this.currentSpeed = speed;
    this.playerService.setSpeed(speed);
    this.avPlayerService.setSpeed(speed);
    this.showSpeedPicker = false;
  }

  private persistCurrentItem(): void {
    if (this.currentMediaItem) {
      this.currentMediaItem.lastPosition = this.currentTime;
      this.currentMediaItem.duration = this.duration;
      this.currentMediaItem.isCompleted = this.isCompleted;
      this.currentMediaItem.lastPlayedAt = Date.now();
      this.storageService.savePlayHistory(this.currentMediaItem);
    }
  }

  private syncCurrentItemProgress(): void {
    if (this.currentMediaItem) {
      this.currentMediaItem.lastPosition = this.currentTime;
      this.currentMediaItem.duration = this.duration;
      this.currentMediaItem.isCompleted = false;
    }
  }

  private markCurrentPlaySession(): void {
    if (this.currentMediaItem && !this.sessionPlayCountRecorded) {
      this.currentMediaItem.playCount += 1;
      this.currentMediaItem.lastPlayedAt = Date.now();
      this.sessionPlayCountRecorded = true;
      this.storageService.savePlayHistory(this.currentMediaItem);
      this.loadCollections();
    }
  }

  private togglePlay(): void {
    if (!this.currentMediaItem || !this.isPrepared || this.hasPlayableError) {
      return;
    }

    if (this.isPlaying) {
      if (this.isUsingAVPlayer()) {
        this.avPlayerService.pause();
      } else {
        this.videoController.pause();
      }
      this.isPlaying = false;
      this.persistCurrentItem();
      return;
    }

    if (this.isUsingAVPlayer()) {
      this.avPlayerService.play();
    } else {
      this.videoController.start();
    }
    this.isPlaying = true;
  }

  private stopPlayback(): void {
    if (!this.currentMediaItem || !this.isPrepared) {
      return;
    }

    if (this.isUsingAVPlayer()) {
      this.avPlayerService.stop();
    } else {
      this.videoController.stop();
    }
    this.backgroundPlaybackService.ensureStopped();
    this.isPlaying = false;
    this.currentTime = 0;
    this.isCompleted = false;
    if (this.currentMediaItem) {
      this.currentMediaItem.lastPosition = 0;
      this.currentMediaItem.isCompleted = false;
    }
    this.persistCurrentItem();
  }

  private replayCurrent(): void {
    if (!this.currentMediaItem || !this.isPrepared) {
      return;
    }

    this.currentTime = 0;
    this.isCompleted = false;
    this.currentMediaItem.isCompleted = false;
    this.currentMediaItem.lastPosition = 0;
    if (this.isUsingAVPlayer()) {
      this.avPlayerService.seek(0);
      this.avPlayerService.play();
    } else {
      this.videoController.setCurrentTime(0, SeekMode.Accurate);
      this.videoController.start();
    }
    this.isPlaying = true;
    this.startBackgroundPlaybackIfNeeded();
  }

  private retryCurrent(): void {
    if (!this.currentMediaItem) {
      return;
    }

    this.currentTime = this.currentMediaItem.lastPosition;
    this.duration = this.currentMediaItem.duration;
    this.resetPlaybackFlags();
    if (this.isUsingAVPlayer() && this.avPlayerSurfaceId.length > 0) {
      this.avPlayerService.open(this.currentMediaItem.uri, true);
    } else if (!this.isUsingAVPlayer()) {
      this.videoSessionKey++;
    }
  }

  private async toggleFavorite(item: MediaItem): Promise<void> {
    const result = await this.storageService.toggleFavorite(item.uri);
    if (this.currentMediaItem && this.currentMediaItem.uri === item.uri) {
      this.currentMediaItem.isFavorite = result;
    }
    await this.loadCollections();
  }

  private onSliderChange(value: number): void {
    this.currentTime = value;
    this.isDraggingProgress = true;
  }

  private onSliderTouch(event: TouchEvent): void {
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.isDraggingProgress = false;
      if (this.isPrepared) {
        if (this.isUsingAVPlayer()) {
          this.avPlayerService.seek(this.currentTime);
        } else {
          this.videoController.setCurrentTime(this.currentTime, SeekMode.Accurate);
        }
      }
      this.updateSubtitleRender(this.currentTime);
      this.maybeUpdateBackgroundSession();
      this.persistCurrentItem();
    }
  }

  private updatePlaylist(): void {
    this.playlistItems = this.playerService.getPlaylist().getItems();
  }

  private formatTime(seconds: number): string {
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
  }

  private formatDateTime(timestamp: number): string {
    if (timestamp <= 0) {
      return '--';
    }
    const date = new Date(timestamp);
    const month = `${date.getMonth() + 1}`.padStart(2, '0');
    const day = `${date.getDate()}`.padStart(2, '0');
    const hours = `${date.getHours()}`.padStart(2, '0');
    const minutes = `${date.getMinutes()}`.padStart(2, '0');
    return `${month}-${day} ${hours}:${minutes}`;
  }

  private getPlaybackStatusText(): string {
    if (this.hasPlayableError) {
      return '播放异常';
    }
    if (this.isCompleted) {
      return '已播放完成';
    }
    if (this.isPlaying) {
      return '播放中';
    }
    if (this.isPrepared) {
      return '已暂停';
    }
    return '加载中';
  }

  private getKernelStatusText(): string {
    const currentKernel = this.playerKernelService.getKernelByMode(this.playerKernelMode);
    return `${currentKernel.displayName} · ${currentKernel.status}`;
  }

  private getScaleModeLabel(): string {
    return this.fitMode === 'cover' ? '填充' : '适应';
  }

  private getVisibleLibraryItems(): MediaItem[] {
    if (this.activeLibraryTab === 'recent') {
      return this.historyItems;
    }
    if (this.activeLibraryTab === 'favorites') {
      return this.favoriteItems;
    }
    if (this.activeLibraryTab === 'folders') {
      if (this.selectedFolderName === ALL_FOLDERS_LABEL) {
        return this.libraryItems;
      }
      return this.libraryItems.filter((item: MediaItem) => item.folderName === this.selectedFolderName);
    }
    return this.libraryItems;
  }

  build() {
    Column() {
      if (this.currentMediaItem) {
        Stack({ alignContent: Alignment.BottomCenter }) {
          if (this.isUsingAVPlayer()) {
            XComponent({
              id: 'player_sirius_surface',
              type: XComponentType.SURFACE,
              controller: this.xComponentController
            })
              .width('100%')
              .height(this.isLandscapeMode ? 420 : 300)
              .backgroundColor(Color.Black)
              .onLoad(() => {
                this.onAVPlayerSurfaceLoad();
              });
          } else {
            ForEach([this.videoSessionKey], (_sessionKey: number) => {
              Video({
                src: this.currentMediaItem.uri,
                currentProgressRate: this.currentSpeed,
                previewUri: '',
                controller: this.videoController
              })
                .width('100%')
                .height(this.isLandscapeMode ? 420 : 300)
                .autoPlay(true)
                .controls(false)
                .muted(this.playerVolume <= 0)
                .objectFit(this.getObjectFitMode())
                .rotate({ angle: this.videoRotation })
                .onPrepared((duration: number) => {
                  this.duration = duration;
                  this.isPrepared = true;
                  this.isLoading = false;
                  if (this.currentMediaItem) {
                    this.currentMediaItem.duration = duration;
                    this.currentMediaItem.isCompleted = false;
                  }
                  if (this.currentTime > 0) {
                    this.currentTime = Math.min(this.currentTime, duration);
                    this.videoController.setCurrentTime(this.currentTime, SeekMode.Accurate);
                  }
                  this.maybeUpdateBackgroundSession();
                })
                .onUpdate((time: number) => {
                  if (!this.isDraggingProgress) {
                    this.currentTime = time;
                    this.syncCurrentItemProgress();
                    this.updateSubtitleRender(time);
                    this.maybeUpdateBackgroundSession();
                  }
                })
                .onStart(() => {
                  this.isPlaying = true;
                  this.isLoading = false;
                  this.markCurrentPlaySession();
                  this.startBackgroundPlaybackIfNeeded();
                })
                .onPause(() => {
                  this.isPlaying = false;
                  this.persistCurrentItem();
                  this.backgroundPlaybackService.ensureStopped();
                })
                .onFinish(() => {
                  this.isPlaying = false;
                  this.isCompleted = true;
                  this.currentTime = 0;
                  this.updateSubtitleRender(0);
                  this.backgroundPlaybackService.ensureStopped();
                  if (this.currentMediaItem) {
                    this.currentMediaItem.lastPosition = 0;
                    this.currentMediaItem.isCompleted = true;
                    this.currentMediaItem.lastPlayedAt = Date.now();
                  }
                  this.persistCurrentItem();
                })
                .onError(() => {
                  const networkMessage = this.currentMediaItem?.sourceType === 'network'
                    ? '网络播放失败，请检查链接是否有效、网络是否较弱，或稍后重试。'
                    : '视频播放失败，可能是文件不可访问或格式暂不支持。';
                  this.handlePlaybackFailure(networkMessage);
                  this.backgroundPlaybackService.ensureStopped();
                });
            }, (sessionKey: number) => sessionKey.toString());
          }

          if (this.gestureHint.length > 0) {
            Text(this.gestureHint)
              .fontSize(12)
              .fontColor(Color.White)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .backgroundColor('#99000000')
              .borderRadius(16)
              .margin({ bottom: 14 });
          }

          if (this.subtitleText.length > 0) {
            Text(this.subtitleText)
              .fontSize(16)
              .fontColor(Color.White)
              .textAlign(TextAlign.Center)
              .maxLines(3)
              .textOverflow({ overflow: TextOverflow.Clip })
              .padding({ left: 14, right: 14, top: 8, bottom: 8 })
              .backgroundColor('#66000000')
              .borderRadius(10)
              .margin({ bottom: 52 })
              .width('92%');
          }
        }
        .gesture(
          PanGesture()
            .onActionUpdate((event: GestureEvent) => {
              if (Math.abs(event.offsetX) >= Math.abs(event.offsetY)) {
                this.adjustProgress(event.offsetX > 0 ? 3 : -3);
              } else {
                this.adjustVolume(event.offsetY < 0 ? 0.02 : -0.02);
              }
            })
            .onActionEnd(() => {
              this.persistCurrentItem();
            })
        );
      } else {
        Column() {
          Text('请选择本地视频或输入网络地址')
            .fontSize(18)
            .fontColor(Color.Gray);

          if (this.errorMessage.length > 0) {
            Text(this.errorMessage)
              .fontSize(13)
              .fontColor('#D9485F')
              .margin({ top: 12 });
          }

          if (this.showPermissionGuide) {
            Button('去授权')
              .margin({ top: 12 })
              .onClick(async () => {
                const granted = await this.ensureMediaPermission(true);
                if (granted) {
                  this.errorMessage = '';
                }
              });
          }

          Button('选择视频')
            .width(150)
            .margin({ top: 20 })
            .onClick(() => {
              this.selectVideo();
            });

          Button('扫描媒体库')
            .width(150)
            .margin({ top: 12 })
            .onClick(() => {
              this.importMediaLibrary();
            });
        }
        .width('100%')
        .height(300)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#F0F0F0');
      }

      Column() {
        if (this.currentMediaItem) {
          Text(this.currentMediaItem.title)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ bottom: 10 });
        }

        Row() {
          Button('选择视频')
            .fontSize(14)
            .onClick(() => {
              this.selectVideo();
            });

          Button('扫描媒体库')
            .fontSize(14)
            .margin({ left: 10 })
            .onClick(() => {
              this.importMediaLibrary();
            });

          Button('媒体库')
            .fontSize(14)
            .margin({ left: 10 })
            .onClick(() => {
              this.activeLibraryTab = 'library';
              this.showLibrary = true;
            });
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
        .margin({ bottom: 10 });

        Row() {
          Button('ArkUI Video')
            .fontSize(12)
            .backgroundColor(this.playerKernelMode === 'video-component' ? '#007DFF' : '#F3F4F6')
            .fontColor(this.playerKernelMode === 'video-component' ? Color.White : Color.Black)
            .onClick(() => {
              this.switchKernel('video-component');
            });

          Button('AVPlayer')
            .fontSize(12)
            .margin({ left: 8 })
            .backgroundColor(this.playerKernelMode === 'avplayer-native' ? '#007DFF' : '#F3F4F6')
            .fontColor(this.playerKernelMode === 'avplayer-native' ? Color.White : Color.Black)
            .onClick(() => {
              this.switchKernel('avplayer-native');
            });

          Text(this.getKernelStatusText())
            .fontSize(12)
            .fontColor('#6B7280')
            .margin({ left: 12 })
            .layoutWeight(1);
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ bottom: 12 });

        Row() {
          Button('历史记录')
            .fontSize(14)
            .onClick(() => {
              this.showHistory = true;
            });

          Button('播放列表')
            .fontSize(14)
            .margin({ left: 10 })
            .onClick(() => {
              this.updatePlaylist();
              this.showPlaylist = true;
            });

          Button(this.currentMediaItem?.isFavorite ? '取消收藏' : '收藏')
            .fontSize(14)
            .margin({ left: 10 })
            .enabled(!!this.currentMediaItem)
            .onClick(() => {
              if (this.currentMediaItem) {
                this.toggleFavorite(this.currentMediaItem);
              }
            });
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
        .margin({ bottom: 12 });

        Row() {
          Button(this.isLandscapeMode ? '竖屏' : '横屏')
            .fontSize(14)
            .onClick(() => {
              this.toggleOrientation();
            });

          Button(`画面${this.getScaleModeLabel()}`)
            .fontSize(14)
            .margin({ left: 10 })
            .onClick(() => {
              this.cycleFitMode();
            });

          Button('旋转画面')
            .fontSize(14)
            .margin({ left: 10 })
            .onClick(() => {
              this.rotateVideo();
            });

          Button('字幕/音轨')
            .fontSize(14)
            .margin({ left: 10 })
            .onClick(() => {
              this.showTrackPanel = true;
            });
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
        .margin({ bottom: 12 });

        if (this.errorMessage.length > 0) {
          Text(this.errorMessage)
            .fontSize(13)
            .fontColor('#D9485F')
            .width('100%')
            .margin({ bottom: 12 });
        }

        if (this.libraryMessage.length > 0) {
          Text(this.libraryMessage)
            .fontSize(12)
            .fontColor('#2563EB')
            .width('100%')
            .margin({ bottom: 12 });
        }

        if (this.showPermissionGuide) {
          Row() {
            Text('媒体访问权限未开启')
              .fontSize(13)
              .fontColor('#B45309');

            Button('去授权')
              .fontSize(12)
              .margin({ left: 12 })
              .onClick(async () => {
                const granted = await this.ensureMediaPermission(true);
                if (granted) {
                  this.errorMessage = '';
                }
              });
          }
          .width('100%')
          .margin({ bottom: 12 });
        }

        Column() {
          Row() {
            Text('网络播放')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .layoutWeight(1);

            Button(this.showNetworkInput ? '收起' : '展开')
              .fontSize(12)
              .onClick(() => {
                this.showNetworkInput = !this.showNetworkInput;
              });

            Button('WebDAV')
              .fontSize(12)
              .margin({ left: 8 })
              .onClick(() => {
                this.showRemotePanel = true;
              });

            Button('投屏')
              .fontSize(12)
              .margin({ left: 8 })
              .onClick(() => {
                this.showCastingPanel = true;
              });
          }
          .width('100%');

          if (this.showNetworkInput) {
            TextInput({ text: this.networkUrl, placeholder: '输入 HTTP/HTTPS 或 m3u8 地址' })
              .width('100%')
              .margin({ top: 10 })
              .backgroundColor('#F3F4F6')
              .borderRadius(10)
              .onChange((value: string) => {
                this.networkUrl = value;
              });

            Row() {
              Button('打开链接')
                .fontSize(14)
                .onClick(() => {
                  this.openNetworkMedia();
                });

              Button('HLS 示例')
                .fontSize(14)
                .margin({ left: 10 })
                .onClick(() => {
                  this.networkUrl = 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8';
                });
            }
            .margin({ top: 10 });
          }
        }
        .width('100%')
        .padding(12)
        .borderRadius(12)
        .backgroundColor('#F9FAFB')
        .margin({ bottom: 12 });

        if (this.currentMediaItem) {
          Column() {
            Row() {
              Text('媒体元数据')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .layoutWeight(1);

              Button('信息面板')
                .fontSize(12)
                .onClick(() => {
                  this.showMediaInfo = true;
                });
            }
            .width('100%')
            .margin({ bottom: 8 });

            Text(`当前内核：${this.getKernelStatusText()}`)
              .fontSize(14)
              .width('100%');

            Text(`来源：${this.currentMediaItem.sourceType === 'network' ? '网络流' : '本地文件'}`)
              .fontSize(12)
              .width('100%');
            Text(`文件夹：${this.currentMediaItem.folderName}`)
              .fontSize(12)
              .width('100%')
              .margin({ top: 4 });
            Text(`时长：${this.formatTime(this.duration)}`)
              .fontSize(12)
              .width('100%')
              .margin({ top: 4 });
            Text(`进度：${this.formatTime(this.currentTime)} / ${this.formatTime(this.duration)}`)
              .fontSize(12)
              .width('100%')
              .margin({ top: 4 });
            Text(`状态：${this.currentMediaItem.isCompleted || this.isCompleted ? '已完成' : '未完成'}`)
              .fontSize(12)
              .width('100%')
              .margin({ top: 4 });
            Text(`最近播放：${this.formatDateTime(this.currentMediaItem.lastPlayedAt)}`)
              .fontSize(12)
              .width('100%')
              .margin({ top: 4 });
            Text(`播放次数：${this.currentMediaItem.playCount}`)
              .fontSize(12)
              .width('100%')
              .margin({ top: 4 });
            Text(`音量：${this.getVolumeDisplayText()} · 字幕：${this.currentSubtitleLabel} · 音轨：${this.currentAudioTrack}`)
              .fontSize(12)
              .width('100%')
              .margin({ top: 4 });
          }
          .width('100%')
          .padding(12)
          .borderRadius(12)
          .backgroundColor('#F9FAFB')
          .margin({ bottom: 12 });
        }

        Column() {
          Text('手势快调')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .width('100%');

          Text('在画面区域横向滑动快进/快退，纵向滑动调节音量；也可使用下面的快捷按钮。')
            .fontSize(12)
            .fontColor('#6B7280')
            .width('100%')
            .margin({ top: 4 });

          Row() {
            Button(this.getVolumeDownLabel())
              .fontSize(12)
              .onClick(() => {
                this.adjustVolume(-0.1);
              });

            Button(this.getVolumeUpLabel())
              .fontSize(12)
              .margin({ left: 8 })
              .onClick(() => {
                this.adjustVolume(0.1);
              });

            Button('-10秒')
              .fontSize(12)
              .margin({ left: 8 })
              .onClick(() => {
                this.adjustProgress(-10);
              });

            Button('+10秒')
              .fontSize(12)
              .margin({ left: 8 })
              .onClick(() => {
                this.adjustProgress(10);
              });
          }
          .width('100%')
          .margin({ top: 10 });
        }
        .width('100%')
        .padding(12)
        .borderRadius(12)
        .backgroundColor('#F9FAFB')
        .margin({ bottom: 12 });

        Row() {
          Button('|<')
            .width(50)
            .enabled(this.playlistItems.length > 1)
            .onClick(() => {
              this.playPrevious();
            });

          Button(this.isPlaying ? '暂停' : '播放')
            .width(80)
            .margin({ left: 10, right: 10 })
            .enabled(this.isPrepared)
            .onClick(() => {
              this.togglePlay();
            });

          Button('>|')
            .width(50)
            .enabled(this.playlistItems.length > 1)
            .onClick(() => {
              this.playNext();
            });

          Button('停止')
            .width(60)
            .margin({ left: 10 })
            .enabled(this.isPrepared)
            .onClick(() => {
              this.stopPlayback();
            });

          Blank()
            .layoutWeight(1);

          Button(`${this.currentSpeed}x`)
            .width(70)
            .margin({ left: 10, right: 10 })
            .onClick(() => {
              this.showSpeedPicker = true;
            });
        }
        .margin({ bottom: 15 });

        if (this.hasPlayableError) {
          Row() {
            Button('重试')
              .width(90)
              .onClick(() => {
                this.retryCurrent();
              });

            Button('重新选择')
              .width(110)
              .margin({ left: 12 })
              .onClick(() => {
                this.selectVideo();
              });
          }
          .width('100%')
          .margin({ bottom: 12 });
        }

        if (this.isCompleted) {
          Row() {
            Button('重播')
              .width(90)
              .onClick(() => {
                this.replayCurrent();
              });

            Button('下一项')
              .width(110)
              .margin({ left: 12 })
              .enabled(this.playlistItems.length > 1)
              .onClick(() => {
                this.playNext();
              });
          }
          .width('100%')
          .margin({ bottom: 12 });
        }

        Row() {
          Text(this.formatTime(this.currentTime))
            .fontSize(13)
            .width(48);

          Slider({
            value: this.currentTime,
            min: 0,
            max: this.duration > 0 ? this.duration : 1,
            step: 1,
            style: SliderStyle.OutSet
          })
            .layoutWeight(1)
            .margin({ left: 12, right: 12 })
            .enabled(this.isPrepared)
            .blockColor('#007DFF')
            .trackColor('#D1D5DB')
            .selectedColor('#2563EB')
            .onChange((value: number) => {
              this.onSliderChange(value);
            })
            .onTouch((event: TouchEvent) => {
              this.onSliderTouch(event);
            });

          Text(this.formatTime(this.duration))
            .fontSize(13)
            .width(48);
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ bottom: 12 });

        Text(this.getPlaybackStatusText())
          .fontSize(13)
          .fontColor(this.isPlaying ? '#007DFF' : '#666666')
          .width('100%');

        if (this.isLoading) {
          Text('正在加载媒体信息...')
            .fontSize(12)
            .fontColor('#666666')
            .width('100%')
            .margin({ top: 6 });
        }

        Text('当前已补充横竖屏、画面比例/旋转、滑动快调和信息面板；字幕、多音轨、后台播放等高级能力仍建议切换到 AVPlayer 或 Native 内核。')
          .fontSize(11)
          .fontColor('#6B7280')
          .width('100%')
          .margin({ top: 12 });
      }
      .width('100%')
      .padding(20);
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
    .bindSheet($$this.showSpeedPicker, this.SpeedPickerBuilder(), {
      height: 300,
      dragBar: true,
      onDisappear: () => {
        this.showSpeedPicker = false;
      }
    })
    .bindSheet($$this.showPlaylist, this.PlaylistBuilder(), {
      height: 420,
      dragBar: true,
      onDisappear: () => {
        this.showPlaylist = false;
      }
    })
    .bindSheet($$this.showHistory, this.HistoryBuilder(), {
      height: 420,
      dragBar: true,
      onDisappear: () => {
        this.showHistory = false;
      }
    })
    .bindSheet($$this.showLibrary, this.LibraryBuilder(), {
      height: 520,
      dragBar: true,
      onDisappear: () => {
        this.showLibrary = false;
      }
    })
    .bindSheet($$this.showResumePrompt, this.ResumePromptBuilder(), {
      height: 260,
      dragBar: true,
      onDisappear: () => {
        this.showResumePrompt = false;
      }
    })
    .bindSheet($$this.showMediaInfo, this.MediaInfoBuilder(), {
      height: 420,
      dragBar: true,
      onDisappear: () => {
        this.showMediaInfo = false;
      }
    })
    .bindSheet($$this.showTrackPanel, this.TrackPanelBuilder(), {
      height: 420,
      dragBar: true,
      onDisappear: () => {
        this.showTrackPanel = false;
      }
    })
    .bindSheet($$this.showRemotePanel, this.RemotePanelBuilder(), {
      height: 560,
      dragBar: true,
      onDisappear: () => {
        this.showRemotePanel = false;
      }
    })
    .bindSheet($$this.showCastingPanel, this.CastingPanelBuilder(), {
      height: 520,
      dragBar: true,
      onDisappear: () => {
        this.showCastingPanel = false;
      }
    });
  }

  @Builder
  SpeedPickerBuilder() {
    Column() {
      Text('选择播放速度')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .margin({ top: 20, bottom: 20 });

      List({ space: 10 }) {
        ForEach(PLAYBACK_SPEEDS, (speed: number) => {
          ListItem() {
            Text(`${speed}x`)
              .fontSize(16)
              .width('100%')
              .height(50)
              .textAlign(TextAlign.Center)
              .borderRadius(8)
              .backgroundColor(speed === this.currentSpeed ? '#007DFF' : '#F0F0F0')
              .fontColor(speed === this.currentSpeed ? Color.White : Color.Black)
              .onClick(() => {
                this.changeSpeed(speed);
              });
          }
        }, (speed: number) => speed.toString());
      }
      .width('90%')
      .height('80%')
      .padding({ left: 10, right: 10 });
    }
    .width('100%')
    .height('100%');
  }

  @Builder
  PlaylistBuilder() {
    Column() {
      Text('播放列表')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .margin({ top: 20, bottom: 20 });

      if (this.playlistItems.length === 0) {
        Text('播放列表为空')
          .fontSize(16)
          .fontColor(Color.Gray);
      } else {
        List({ space: 8 }) {
          ForEach(this.playlistItems, (item: MediaItem, index: number) => {
            ListItem() {
              Row() {
                Text(item.title)
                  .fontSize(14)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1);

                if (item.isFavorite) {
                  Text('已收藏')
                    .fontSize(12)
                    .fontColor('#F59E0B')
                    .margin({ right: 8 });
                }

                if (index === this.playerService.getPlaylist().getCurrentIndex()) {
                  Text('播放中')
                    .fontSize(12)
                    .fontColor('#007DFF');
                }
              }
              .width('100%')
              .height(54)
              .padding({ left: 15, right: 15 })
              .borderRadius(8)
              .backgroundColor(index === this.playerService.getPlaylist().getCurrentIndex() ? '#E8F4FF' : '#F8F8F8')
              .onClick(() => {
                this.playFromPlaylist(index);
              });
            }
          }, (item: MediaItem) => item.id);
        }
        .width('90%')
        .height('80%')
        .padding({ left: 10, right: 10 });
      }
    }
    .width('100%')
    .height('100%');
  }

  @Builder
  HistoryBuilder() {
    Column() {
      Text('播放历史')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .margin({ top: 20, bottom: 20 });

      if (this.historyItems.length === 0) {
        Text('暂无播放历史')
          .fontSize(16)
          .fontColor(Color.Gray);
      } else {
        List({ space: 8 }) {
          ForEach(this.historyItems, (item: MediaItem) => {
            ListItem() {
              Column() {
                Text(item.title)
                  .fontSize(14)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%');

                Text(`最近播放：${this.formatDateTime(item.lastPlayedAt)}`)
                  .fontSize(12)
                  .fontColor(Color.Gray)
                  .width('100%')
                  .margin({ top: 4 });

                Text(item.isCompleted ? '状态：已播放完成' : `上次位置：${this.formatTime(item.lastPosition)}`)
                  .fontSize(12)
                  .fontColor(item.isCompleted ? '#059669' : Color.Gray)
                  .width('100%')
                  .margin({ top: 4 });
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding({ left: 15, right: 15, top: 10, bottom: 10 })
              .borderRadius(8)
              .backgroundColor('#F8F8F8')
              .onClick(() => {
                this.openFromHistory(item);
              });
            }
          }, (item: MediaItem) => item.id);
        }
        .width('90%')
        .height('80%')
        .padding({ left: 10, right: 10 });
      }
    }
    .width('100%')
    .height('100%');
  }

  @Builder
  LibraryBuilder() {
    const visibleItems = this.getVisibleLibraryItems();

    Column() {
      Text('媒体库')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .margin({ top: 20, bottom: 16 });

      Row() {
        Button('最近播放')
          .fontSize(12)
          .backgroundColor(this.activeLibraryTab === 'recent' ? '#007DFF' : '#F3F4F6')
          .fontColor(this.activeLibraryTab === 'recent' ? Color.White : Color.Black)
          .onClick(() => {
            this.activeLibraryTab = 'recent';
          });

        Button('收藏')
          .fontSize(12)
          .margin({ left: 8 })
          .backgroundColor(this.activeLibraryTab === 'favorites' ? '#007DFF' : '#F3F4F6')
          .fontColor(this.activeLibraryTab === 'favorites' ? Color.White : Color.Black)
          .onClick(() => {
            this.activeLibraryTab = 'favorites';
          });

        Button('全部媒体')
          .fontSize(12)
          .margin({ left: 8 })
          .backgroundColor(this.activeLibraryTab === 'library' ? '#007DFF' : '#F3F4F6')
          .fontColor(this.activeLibraryTab === 'library' ? Color.White : Color.Black)
          .onClick(() => {
            this.activeLibraryTab = 'library';
          });

        Button('文件夹')
          .fontSize(12)
          .margin({ left: 8 })
          .backgroundColor(this.activeLibraryTab === 'folders' ? '#007DFF' : '#F3F4F6')
          .fontColor(this.activeLibraryTab === 'folders' ? Color.White : Color.Black)
          .onClick(() => {
            this.activeLibraryTab = 'folders';
          });
      }
      .width('92%')
      .margin({ bottom: 12 });

      if (this.activeLibraryTab === 'folders') {
        List({ initialIndex: 0, space: 8 }) {
          ForEach(this.folderNames, (folderName: string) => {
            ListItem() {
              Text(folderName)
                .fontSize(13)
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .borderRadius(16)
                .backgroundColor(this.selectedFolderName === folderName ? '#DBEAFE' : '#F3F4F6')
                .fontColor(this.selectedFolderName === folderName ? '#1D4ED8' : Color.Black)
                .onClick(() => {
                  this.selectedFolderName = folderName;
                });
            }
          }, (folderName: string) => folderName);
        }
        .width('92%')
        .height(48)
        .listDirection(Axis.Horizontal)
        .margin({ bottom: 12 });
      }

      if (visibleItems.length === 0) {
        Text('当前视图暂无媒体')
          .fontSize(16)
          .fontColor(Color.Gray);
      } else {
        List({ space: 8 }) {
          ForEach(visibleItems, (item: MediaItem) => {
            ListItem() {
              Column() {
                Row() {
                  Text(item.title)
                    .fontSize(14)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1);

                  Text(item.isFavorite ? '已收藏' : '收藏')
                    .fontSize(12)
                    .fontColor(item.isFavorite ? '#F59E0B' : '#6B7280')
                    .onClick(() => {
                      this.toggleFavorite(item);
                    });
                }
                .width('100%');

                Text(`${item.sourceType === 'network' ? '网络流' : item.folderName} · ${item.isCompleted ? '已完成' : this.formatTime(item.lastPosition)}`)
                  .fontSize(12)
                  .fontColor(Color.Gray)
                  .width('100%')
                  .margin({ top: 4 });

                Text(`最近播放：${this.formatDateTime(item.lastPlayedAt)}`)
                  .fontSize(12)
                  .fontColor(Color.Gray)
                  .width('100%')
                  .margin({ top: 4 });
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding({ left: 15, right: 15, top: 12, bottom: 12 })
              .borderRadius(8)
              .backgroundColor('#F8F8F8')
              .onClick(() => {
                this.openFromLibrary(item);
              });
            }
          }, (item: MediaItem) => item.id);
        }
        .width('92%')
        .height('72%');
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center);
  }

  @Builder
  MediaInfoBuilder() {
    Column() {
      Text('媒体信息面板')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .margin({ top: 20, bottom: 16 });

      if (this.currentMediaItem) {
        List({ space: 10 }) {
          ListItem() {
            Text(`标题：${this.currentMediaItem.title}`);
          }
          ListItem() {
            Text(`URI：${this.currentMediaItem.uri}`);
          }
          ListItem() {
            Text(`来源：${this.currentMediaItem.sourceType === 'network' ? '网络流' : '本地文件'}`);
          }
          ListItem() {
            Text(`文件夹：${this.currentMediaItem.folderName}`);
          }
          ListItem() {
            Text(`内核：${this.getKernelStatusText()}`);
          }
          ListItem() {
            Text(`画面：${this.getScaleModeLabel()} · 旋转 ${this.videoRotation}°`);
          }
          ListItem() {
            Text(`音量：${this.getVolumeDisplayText()} · 倍速 ${this.currentSpeed}x`);
          }
          ListItem() {
            Text(`字幕：${this.currentSubtitleLabel} · 偏移 ${this.subtitleOffsetSeconds}s`);
          }
          ListItem() {
            Text(`音轨：${this.currentAudioTrack}`);
          }
        }
        .width('90%')
        .height('76%');
      } else {
        Text('当前没有媒体信息')
          .fontSize(16)
          .fontColor(Color.Gray);
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center);
  }

  @Builder
  TrackPanelBuilder() {
    Column() {
      Text('字幕与音轨')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .margin({ top: 20, bottom: 16 });

      Row() {
        Button('选择字幕文件')
          .fontSize(14)
          .enabled(this.supportsSubtitleFeature())
          .onClick(() => {
            this.pickSubtitleFile();
          });

        Button('清除字幕')
          .fontSize(14)
          .margin({ left: 10 })
          .enabled(this.subtitleUri.length > 0)
          .onClick(() => {
            this.clearSubtitle();
          });
      }
      .width('90%')
      .margin({ bottom: 12 });

      Row() {
        Button(this.subtitleEnabled ? '关闭字幕' : '开启字幕')
          .fontSize(14)
          .enabled(this.supportsSubtitleFeature())
          .onClick(() => {
            this.toggleSubtitle();
          });

        Button('-偏移')
          .fontSize(14)
          .margin({ left: 10 })
          .enabled(this.supportsSubtitleOffsetFeature())
          .onClick(() => {
            this.adjustSubtitleOffset(-1);
          });

        Button('+偏移')
          .fontSize(14)
          .margin({ left: 10 })
          .enabled(this.supportsSubtitleOffsetFeature())
          .onClick(() => {
            this.adjustSubtitleOffset(1);
          });
      }
      .width('90%')
      .margin({ bottom: 12 });

      Text(`字幕状态：${this.currentSubtitleLabel}`)
        .fontSize(13)
        .width('90%');
      Text(`字幕文件：${this.getSubtitleFileName()}`)
        .fontSize(12)
        .fontColor('#6B7280')
        .width('90%')
        .margin({ top: 6 });
      Text(`字幕偏移：${this.subtitleOffsetSeconds}s`)
        .fontSize(13)
        .width('90%')
        .margin({ top: 6, bottom: 16 });

      if (this.subtitleMessage.length > 0) {
        Text(this.subtitleMessage)
          .fontSize(12)
          .fontColor('#2563EB')
          .width('90%')
          .margin({ bottom: 12 });
      }

      Text('音轨切换')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .width('90%')
        .margin({ bottom: 10 });

      List({ space: 8 }) {
        ForEach(['默认音轨'], (trackName: string) => {
          ListItem() {
            Row() {
              Text(trackName)
                .fontSize(14)
                .layoutWeight(1);

              if (this.selectedAudioTrackIndex < 0) {
                Text('当前')
                  .fontSize(12)
                  .fontColor('#007DFF');
              }
            }
            .width('100%')
            .padding({ left: 15, right: 15, top: 12, bottom: 12 })
            .borderRadius(8)
            .backgroundColor('#F8F8F8')
            .enabled(this.supportsAudioTrackFeature())
            .onClick(() => {
              this.selectAudioTrackByIndex(-1);
            });
          }
        }, (trackName: string) => trackName);

        ForEach(this.audioTracks, (track: AVPlayerTrackSummary) => {
          ListItem() {
            Row() {
              Text(track.label)
                .fontSize(14)
                .layoutWeight(1);

              if (this.selectedAudioTrackIndex === track.trackIndex) {
                Text('当前')
                  .fontSize(12)
                  .fontColor('#007DFF');
              }
            }
            .width('100%')
            .padding({ left: 15, right: 15, top: 12, bottom: 12 })
            .borderRadius(8)
            .backgroundColor('#F8F8F8')
            .enabled(this.supportsAudioTrackFeature())
            .onClick(() => {
              this.selectAudioTrackByIndex(track.trackIndex);
            });
          }
        }, (track: AVPlayerTrackSummary) => track.trackIndex.toString());
      }
      .width('90%')
      .height('44%');

      Text(this.getTrackPanelHint())
        .fontSize(12)
        .fontColor('#6B7280')
        .width('90%')
        .margin({ top: 12 });
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center);
  }

  @Builder
  RemotePanelBuilder() {
    Column() {
      Text('远端：WebDAV / FTP')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .margin({ top: 20, bottom: 12 });

      Row() {
        Button('WebDAV')
          .fontSize(12)
          .backgroundColor(this.remoteMode === 'webdav' ? '#007DFF' : '#F3F4F6')
          .fontColor(this.remoteMode === 'webdav' ? Color.White : Color.Black)
          .onClick(() => {
            this.remoteMode = 'webdav';
          });
        Button('FTP')
          .fontSize(12)
          .margin({ left: 8 })
          .backgroundColor(this.remoteMode === 'ftp' ? '#007DFF' : '#F3F4F6')
          .fontColor(this.remoteMode === 'ftp' ? Color.White : Color.Black)
          .onClick(() => {
            this.remoteMode = 'ftp';
          });
      }
      .width('90%')
      .margin({ bottom: 12 });

      if (this.remoteMode === 'webdav') {
      TextInput({ text: this.webDavBaseUrl, placeholder: 'WebDAV Base URL，例如 https://example.com/dav' })
        .width('90%')
        .backgroundColor('#F3F4F6')
        .borderRadius(10)
        .onChange((value: string) => {
          this.webDavBaseUrl = value;
        });

      Row() {
        TextInput({ text: this.webDavUsername, placeholder: '用户名（可选）' })
          .layoutWeight(1)
          .backgroundColor('#F3F4F6')
          .borderRadius(10)
          .onChange((value: string) => {
            this.webDavUsername = value;
          });

        TextInput({ text: this.webDavPassword, placeholder: '密码（可选）' })
          .layoutWeight(1)
          .margin({ left: 10 })
          .backgroundColor('#F3F4F6')
          .borderRadius(10)
          .onChange((value: string) => {
            this.webDavPassword = value;
          });
      }
      .width('90%')
      .margin({ top: 10 });

      Row() {
        TextInput({ text: this.webDavPath, placeholder: '路径（例如 / 或 /Movies/ ）' })
          .layoutWeight(1)
          .backgroundColor('#F3F4F6')
          .borderRadius(10)
          .onChange((value: string) => {
            this.webDavPath = value;
          });

        Button(this.webDavLoading ? '加载中' : '列目录')
          .fontSize(14)
          .margin({ left: 10 })
          .enabled(!this.webDavLoading)
          .onClick(() => {
            this.listWebDavDirectory();
          });
      }
      .width('90%')
      .margin({ top: 10, bottom: 12 });

      if (this.webDavMessage.length > 0) {
        Text(this.webDavMessage)
          .fontSize(12)
          .fontColor('#2563EB')
          .width('90%')
          .margin({ bottom: 10 });
      }

      List({ space: 8 }) {
        ForEach(this.webDavEntries, (entry: WebDavEntry) => {
          ListItem() {
            Row() {
              Text(entry.isDirectory ? `[目录] ${entry.name}` : entry.name)
                .fontSize(13)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis });

              if (!entry.isDirectory) {
                Text(entry.sizeBytes > 0 ? `${Math.round(entry.sizeBytes / 1024)}KB` : '')
                  .fontSize(11)
                  .fontColor('#6B7280');
              }
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .borderRadius(8)
            .backgroundColor('#F8F8F8')
            .onClick(() => {
              this.openWebDavEntry(entry);
            });
          }
        }, (entry: WebDavEntry) => entry.href);
      }
      .width('90%')
      .height('58%');

      Text('说明：若填写账号密码，将先下载到缓存再播放；未填写则尝试直链播放。')
        .fontSize(11)
        .fontColor('#6B7280')
        .width('90%')
        .margin({ top: 12 });
      } else {
        TextInput({ text: this.ftpHost, placeholder: 'FTP 主机，例如 192.168.1.2' })
          .width('90%')
          .backgroundColor('#F3F4F6')
          .borderRadius(10)
          .onChange((value: string) => {
            this.ftpHost = value;
          });

        Row() {
          TextInput({ text: this.ftpPort.toString(), placeholder: '端口' })
            .layoutWeight(1)
            .backgroundColor('#F3F4F6')
            .borderRadius(10)
            .onChange((value: string) => {
              this.ftpPort = Number(value) || 21;
            });
          TextInput({ text: this.ftpUsername, placeholder: '用户名（可选）' })
            .layoutWeight(2)
            .margin({ left: 10 })
            .backgroundColor('#F3F4F6')
            .borderRadius(10)
            .onChange((value: string) => {
              this.ftpUsername = value;
            });
        }
        .width('90%')
        .margin({ top: 10 });

        TextInput({ text: this.ftpPassword, placeholder: '密码（可选）' })
          .width('90%')
          .margin({ top: 10 })
          .backgroundColor('#F3F4F6')
          .borderRadius(10)
          .onChange((value: string) => {
            this.ftpPassword = value;
          });

        Row() {
          TextInput({ text: this.ftpPath, placeholder: '路径（例如 / 或 /Movies/ ）' })
            .layoutWeight(1)
            .backgroundColor('#F3F4F6')
            .borderRadius(10)
            .onChange((value: string) => {
              this.ftpPath = value;
            });

          Button(this.ftpLoading ? '加载中' : '列目录')
            .fontSize(14)
            .margin({ left: 10 })
            .enabled(!this.ftpLoading)
            .onClick(() => {
              this.listFtpDirectory();
            });
        }
        .width('90%')
        .margin({ top: 10, bottom: 12 });

        if (this.ftpMessage.length > 0) {
          Text(this.ftpMessage)
            .fontSize(12)
            .fontColor('#2563EB')
            .width('90%')
            .margin({ bottom: 10 });
        }

        List({ space: 8 }) {
          ForEach(this.ftpEntries, (entry: FtpEntry) => {
            ListItem() {
              Row() {
                Text(entry.isDirectory ? `[目录] ${entry.name}` : entry.name)
                  .fontSize(13)
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis });

                if (!entry.isDirectory) {
                  Text(entry.sizeBytes > 0 ? `${Math.round(entry.sizeBytes / 1024)}KB` : '')
                    .fontSize(11)
                    .fontColor('#6B7280');
                }
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .borderRadius(8)
              .backgroundColor('#F8F8F8')
              .onClick(() => {
                this.openFtpEntry(entry);
              });
            }
          }, (entry: FtpEntry) => entry.path);
        }
        .width('90%')
        .height('58%');

        Text('说明：FTP 文件会先下载到缓存再播放（当前为最小实现：PASV + MLSD/LIST + RETR）。')
          .fontSize(11)
          .fontColor('#6B7280')
          .width('90%')
          .margin({ top: 12 });
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center);
  }

  @Builder
  CastingPanelBuilder() {
    Column() {
      Text('DLNA 投屏')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .margin({ top: 20, bottom: 16 });

      Row() {
        Button(this.dlnaLoading ? '搜索中' : '搜索设备')
          .fontSize(14)
          .enabled(!this.dlnaLoading)
          .onClick(() => {
            this.discoverDlnaDevices();
          });

        Button('投送当前媒体')
          .fontSize(14)
          .margin({ left: 10 })
          .enabled(this.getCurrentCastableUrl().length > 0 && this.selectedDlnaDeviceUsn.length > 0)
          .onClick(() => {
            this.castToSelectedDevice();
          });
      }
      .width('90%')
      .margin({ bottom: 12 });

      Row() {
        Button('播放')
          .fontSize(12)
          .enabled(this.selectedDlnaDeviceUsn.length > 0)
          .onClick(() => {
            this.playOnSelectedDevice();
          });
        Button('暂停')
          .fontSize(12)
          .margin({ left: 8 })
          .enabled(this.selectedDlnaDeviceUsn.length > 0)
          .onClick(() => {
            this.pauseOnSelectedDevice();
          });
        Button('停止')
          .fontSize(12)
          .margin({ left: 8 })
          .enabled(this.selectedDlnaDeviceUsn.length > 0)
          .onClick(() => {
            this.stopOnSelectedDevice();
          });
      }
      .width('90%')
      .margin({ bottom: 12 });

      if (this.dlnaMessage.length > 0) {
        Text(this.dlnaMessage)
          .fontSize(12)
          .fontColor('#2563EB')
          .width('90%')
          .margin({ bottom: 10 });
      }

      List({ space: 8 }) {
        ForEach(this.dlnaDevices, (device: DlnaDevice) => {
          ListItem() {
            Row() {
              Text(device.friendlyName)
                .fontSize(14)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis });

              if (this.selectedDlnaDeviceUsn === device.usn) {
                Text('已选中')
                  .fontSize(12)
                  .fontColor('#007DFF');
              }
            }
            .width('100%')
            .padding({ left: 15, right: 15, top: 12, bottom: 12 })
            .borderRadius(8)
            .backgroundColor(this.selectedDlnaDeviceUsn === device.usn ? '#E8F4FF' : '#F8F8F8')
            .onClick(() => {
              this.selectedDlnaDeviceUsn = device.usn;
            });
          }
        }, (device: DlnaDevice) => device.usn);
      }
      .width('90%')
      .height('56%');

      Text('说明：当前仅支持把 HTTP/HTTPS 网络流投送到支持 DLNA AVTransport 的 MediaRenderer，本地文件暂未暴露成本地 HTTP 服务。')
        .fontSize(11)
        .fontColor('#6B7280')
        .width('90%')
        .margin({ top: 12 });
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center);
  }

  @Builder
  ResumePromptBuilder() {
    Column() {
      Text('继续播放')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .margin({ top: 20, bottom: 16 });

      Text(this.pendingOpenItem ? `${this.pendingOpenItem.title} 检测到续播记录` : '检测到续播记录')
        .fontSize(14)
        .textAlign(TextAlign.Center)
        .margin({ left: 24, right: 24, bottom: 8 });

      Text(this.pendingOpenItem ? `上次播放到 ${this.formatTime(this.pendingOpenItem.lastPosition)}，是否从该位置继续？` : '')
        .fontSize(13)
        .fontColor(Color.Gray)
        .textAlign(TextAlign.Center)
        .margin({ left: 24, right: 24, bottom: 20 });

      Row() {
        Button('从头播放')
          .layoutWeight(1)
          .margin({ right: 8 })
          .onClick(() => {
            this.confirmResumePlayback(false);
          });

        Button('继续播放')
          .layoutWeight(1)
          .margin({ left: 8 })
          .onClick(() => {
            this.confirmResumePlayback(true);
          });
      }
      .width('88%');
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center);
  }
}
