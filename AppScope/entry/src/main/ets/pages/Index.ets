import { picker } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { PlayerService, PLAYBACK_SPEEDS } from '../services/PlayerService';
import { PermissionService } from '../services/PermissionService';
import { GlobalContext } from '../common/GlobalContext';
import type { MediaItem } from '../model/MediaItem';
import { MediaItemHelper } from '../model/MediaItem';

@Entry
@Component
struct Index {
  private videoController: VideoController = new VideoController();
  @State currentMediaItem: MediaItem | null = null;
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
  @State playlistItems: MediaItem[] = [];
  @State historyItems: MediaItem[] = [];
  @State errorMessage: string = '';
  private playerService: PlayerService = GlobalContext.getPlayerService();
  private storageService = GlobalContext.getStorageService();
  private permissionService: PermissionService = new PermissionService();

  aboutToAppear(): void {
    this.syncPlayerState();
    this.loadHistory();
  }

  aboutToDisappear(): void {
    this.persistCurrentItem();
  }

  private syncPlayerState(): void {
    this.currentMediaItem = this.playerService.getCurrentItem();
    this.currentSpeed = this.playerService.getSpeed();
    this.updatePlaylist();
  }

  private async loadHistory(): Promise<void> {
    this.historyItems = await this.storageService.getPlayHistory();
  }

  private getUiContext(): common.UIAbilityContext {
    return getContext(this) as common.UIAbilityContext;
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
  }

  private handlePlaybackFailure(message: string): void {
    this.isPrepared = false;
    this.isLoading = false;
    this.isPlaying = false;
    this.hasPlayableError = true;
    this.errorMessage = message;
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

  private async selectVideo(): Promise<void> {
    try {
      this.persistCurrentItem();
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
        const fileName = this.getFileNameFromUri(uri);
        const item = this.playerService.addOrActivate(MediaItemHelper.create(uri, fileName));
        this.currentMediaItem = item;
        this.currentTime = item.lastPosition;
        this.duration = item.duration;
        this.resetPlaybackFlags();
        await this.storageService.savePlayHistory(item);
        this.updatePlaylist();
        await this.loadHistory();
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

  private getFileNameFromUri(uri: string): string {
    const parts = uri.split('/');
    return parts[parts.length - 1] || '未知视频';
  }

  private async playFromHistory(item: MediaItem): Promise<void> {
    this.persistCurrentItem();
    this.currentMediaItem = this.playerService.addOrActivate(item);
    this.currentTime = item.lastPosition;
    this.duration = item.duration;
    this.resetPlaybackFlags();
    await this.storageService.savePlayHistory(item);
    this.updatePlaylist();
    await this.loadHistory();
    this.showHistory = false;
  }

  private playFromPlaylist(index: number): void {
    this.persistCurrentItem();
    const item = this.playerService.selectByIndex(index);
    if (item) {
      this.currentMediaItem = item;
      this.currentTime = item.lastPosition;
      this.duration = item.duration;
      this.resetPlaybackFlags();
    }
    this.showPlaylist = false;
  }

  private playNext(): void {
    this.persistCurrentItem();
    this.currentMediaItem = this.playerService.playNext();
    this.currentTime = this.currentMediaItem?.lastPosition ?? 0;
    this.duration = this.currentMediaItem?.duration ?? 0;
    this.resetPlaybackFlags();
    this.updatePlaylist();
  }

  private playPrevious(): void {
    this.persistCurrentItem();
    this.currentMediaItem = this.playerService.playPrevious();
    this.currentTime = this.currentMediaItem?.lastPosition ?? 0;
    this.duration = this.currentMediaItem?.duration ?? 0;
    this.resetPlaybackFlags();
    this.updatePlaylist();
  }

  private changeSpeed(speed: number): void {
    this.currentSpeed = speed;
    this.playerService.setSpeed(speed);
    this.showSpeedPicker = false;
  }

  private persistCurrentItem(): void {
    if (this.currentMediaItem) {
      this.currentMediaItem.lastPosition = this.currentTime;
      this.currentMediaItem.duration = this.duration;
      this.storageService.savePlayHistory(this.currentMediaItem);
    }
  }

  private syncCurrentItemProgress(): void {
    if (this.currentMediaItem) {
      this.currentMediaItem.lastPosition = this.currentTime;
      this.currentMediaItem.duration = this.duration;
    }
  }

  private togglePlay(): void {
    if (!this.currentMediaItem || !this.isPrepared || this.hasPlayableError) {
      return;
    }

    if (this.isPlaying) {
      this.videoController.pause();
      this.isPlaying = false;
      this.persistCurrentItem();
      return;
    }

    this.videoController.start();
    this.isPlaying = true;
  }

  private stopPlayback(): void {
    if (!this.currentMediaItem || !this.isPrepared) {
      return;
    }

    this.videoController.stop();
    this.isPlaying = false;
    this.currentTime = 0;
    if (this.currentMediaItem) {
      this.currentMediaItem.lastPosition = 0;
    }
    this.persistCurrentItem();
  }

  private replayCurrent(): void {
    if (!this.currentMediaItem || !this.isPrepared) {
      return;
    }

    this.currentTime = 0;
    this.isCompleted = false;
    this.videoController.setCurrentTime(0, SeekMode.Accurate);
    this.videoController.start();
    this.isPlaying = true;
  }

  private retryCurrent(): void {
    if (!this.currentMediaItem) {
      return;
    }

    this.currentTime = this.currentMediaItem.lastPosition;
    this.duration = this.currentMediaItem.duration;
    this.resetPlaybackFlags();
  }

  private onSliderChange(value: number): void {
    this.currentTime = value;
    this.isDraggingProgress = true;
  }

  private onSliderTouch(event: TouchEvent): void {
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.isDraggingProgress = false;
      if (this.isPrepared) {
        this.videoController.setCurrentTime(this.currentTime, SeekMode.Accurate);
      }
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

  build() {
    Column() {
      if (this.currentMediaItem) {
        Video({
          src: this.currentMediaItem.uri,
          currentProgressRate: this.currentSpeed,
          previewUri: '',
          controller: this.videoController
        })
          .width('100%')
          .height(300)
          .autoPlay(true)
          .controls(false)
          .objectFit(ImageFit.Contain)
          .onPrepared((duration: number) => {
            this.duration = duration;
            this.isPrepared = true;
            this.isLoading = false;
            if (this.currentMediaItem) {
              this.currentMediaItem.duration = duration;
            }
            if (this.currentTime > 0) {
              this.currentTime = Math.min(this.currentTime, duration);
              this.videoController.setCurrentTime(this.currentTime, SeekMode.Accurate);
            }
          })
          .onUpdate((time: number) => {
            if (!this.isDraggingProgress) {
              this.currentTime = time;
              this.syncCurrentItemProgress();
            }
          })
          .onStart(() => {
            this.isPlaying = true;
            this.isLoading = false;
          })
          .onPause(() => {
            this.isPlaying = false;
            this.persistCurrentItem();
          })
          .onFinish(() => {
            this.isPlaying = false;
            this.isCompleted = true;
            this.currentTime = 0;
            if (this.currentMediaItem) {
              this.currentMediaItem.lastPosition = 0;
            }
            this.persistCurrentItem();
          })
          .onError(() => {
            this.handlePlaybackFailure('视频播放失败，可能是文件不可访问或格式暂不支持。');
          });
      } else {
        Column() {
          Text('请选择视频文件')
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

          Row() {
            Button('选择视频')
              .fontSize(14)
              .onClick(() => {
                this.selectVideo();
              });

            Button('历史记录')
              .fontSize(14)
              .margin({ left: 10 })
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
          }
          .width('100%')
          .justifyContent(FlexAlign.Start)
          .margin({ bottom: 15 });

          if (this.errorMessage.length > 0) {
            Text(this.errorMessage)
              .fontSize(13)
              .fontColor('#D9485F')
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

          Text(this.isPlaying ? '播放中' : (this.isPrepared ? '已暂停' : '加载中'))
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
        }
      }
      .width('100%')
      .padding(20)
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
      height: 400,
      dragBar: true,
      onDisappear: () => {
        this.showPlaylist = false;
      }
    })
    .bindSheet($$this.showHistory, this.HistoryBuilder(), {
      height: 400,
      dragBar: true,
      onDisappear: () => {
        this.showHistory = false;
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

                if (index === this.playerService.getPlaylist().getCurrentIndex()) {
                  Text('播放中')
                    .fontSize(12)
                    .fontColor('#007DFF');
                }
              }
              .width('100%')
              .height(50)
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
          ForEach(this.historyItems, (item: MediaItem, index: number) => {
            ListItem() {
              Column() {
                Text(item.title)
                  .fontSize(14)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%');

                if (item.lastPosition > 0) {
                  Text(`上次看到: ${this.formatTime(item.lastPosition)}`)
                    .fontSize(12)
                    .fontColor(Color.Gray)
                    .width('100%')
                    .margin({ top: 4 });
                }
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding({ left: 15, right: 15, top: 10, bottom: 10 })
              .borderRadius(8)
              .backgroundColor('#F8F8F8')
              .onClick(() => {
                this.playFromHistory(item);
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
}
