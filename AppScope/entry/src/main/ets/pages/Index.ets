import { picker } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { PlayerService, PLAYBACK_SPEEDS } from '../services/PlayerService';
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
  @State showSpeedPicker: boolean = false;
  @State showPlaylist: boolean = false;
  @State showHistory: boolean = false;
  @State playlistItems: MediaItem[] = [];
  @State historyItems: MediaItem[] = [];
  @State errorMessage: string = '';
  private playerService: PlayerService = GlobalContext.getPlayerService();
  private storageService = GlobalContext.getStorageService();

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

  private async selectVideo(): Promise<void> {
    try {
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
        this.errorMessage = '';
        await this.storageService.savePlayHistory(item);
        this.updatePlaylist();
        await this.loadHistory();
      }
    } catch (err) {
      const error = err as BusinessError;
      console.error(`Select video failed: ${error.code}, ${error.message}`);
    }
  }

  private getFileNameFromUri(uri: string): string {
    const parts = uri.split('/');
    return parts[parts.length - 1] || '未知视频';
  }

  private async playFromHistory(item: MediaItem): Promise<void> {
    this.currentMediaItem = this.playerService.addOrActivate(item);
    this.errorMessage = '';
    await this.storageService.savePlayHistory(item);
    this.updatePlaylist();
    await this.loadHistory();
    this.showHistory = false;
  }

  private playFromPlaylist(index: number): void {
    const item = this.playerService.selectByIndex(index);
    if (item) {
      this.currentMediaItem = item;
      this.errorMessage = '';
    }
    this.showPlaylist = false;
  }

  private playNext(): void {
    this.currentMediaItem = this.playerService.playNext();
    this.updatePlaylist();
  }

  private playPrevious(): void {
    this.currentMediaItem = this.playerService.playPrevious();
    this.updatePlaylist();
  }

  private changeSpeed(speed: number): void {
    this.currentSpeed = speed;
    this.playerService.setSpeed(speed);
    this.showSpeedPicker = false;
  }

  private persistCurrentItem(): void {
    if (this.currentMediaItem) {
      this.storageService.savePlayHistory(this.currentMediaItem);
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
          .controls(true)
          .objectFit(ImageFit.Contain)
          .onStart(() => {
            this.isPlaying = true;
          })
          .onPause(() => {
            this.isPlaying = false;
          })
          .onFinish(() => {
            this.isPlaying = false;
            this.persistCurrentItem();
          })
          .onError(() => {
            this.isPlaying = false;
            this.errorMessage = '视频播放失败，请重新选择媒体文件。';
          });
      } else {
        Column() {
          Text('请选择视频文件')
            .fontSize(18)
            .fontColor(Color.Gray);
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

          Row() {
            Button('|<')
              .width(50)
              .onClick(() => {
                this.playPrevious();
              });

            Text(this.isPlaying ? '播放中' : '已暂停')
              .fontSize(14)
              .fontColor(this.isPlaying ? '#007DFF' : '#666666')
              .margin({ left: 12, right: 12 });

            Button('>|')
              .width(50)
              .onClick(() => {
                this.playNext();
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
