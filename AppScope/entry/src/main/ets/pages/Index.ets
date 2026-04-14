import { AVPlayerState } from '@kit.MediaKit';
import { picker } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { PlayerService } from '../services/PlayerService';

@Entry
@Component
struct Index {
  @State videoUrl: string = '';
  @State currentTime: number = 0;
  @State duration: number = 0;
  @State isPlaying: boolean = false;
  @State playerState: AVPlayerState | null = null;
  @State showControls: boolean = true;
  private playerService: PlayerService = new PlayerService();

  aboutToAppear(): void {
    this.initPlayer();
  }

  aboutToDisappear(): void {
    this.playerService.release();
  }

  private async initPlayer(): Promise<void> {
    try {
      await this.playerService.init();
      this.playerService.setStateChangeListener((state: AVPlayerState) => {
        this.playerState = state;
        this.isPlaying = state === AVPlayerState.PLAYING;
      });
      this.playerService.setTimeUpdateListener((time: number, dur: number) => {
        this.currentTime = time;
        this.duration = dur;
      });
    } catch (err) {
      const error = err as BusinessError;
      console.error(`Init player failed: ${error.code}, ${error.message}`);
    }
  }

  private async selectVideo(): Promise<void> {
    try {
      const photoPicker = new picker.PhotoViewPicker();
      const result = await photoPicker.select({
        MIMEType: picker.PhotoViewMIMETypes.VIDEO_TYPE,
        maxSelectNumber: 1
      });

      if (result.photoUris && result.photoUris.length > 0) {
        this.videoUrl = result.photoUris[0];
        await this.playerService.setUrl(this.videoUrl);
      }
    } catch (err) {
      const error = err as BusinessError;
      console.error(`Select video failed: ${error.code}, ${error.message}`);
    }
  }

  private async togglePlay(): Promise<void> {
    if (!this.videoUrl) {
      return;
    }
    if (this.isPlaying) {
      await this.playerService.pause();
    } else {
      await this.playerService.play();
    }
  }

  private async onSeekChange(value: number): Promise<void> {
    this.currentTime = value;
    await this.playerService.seek(value);
  }

  private formatTime(seconds: number): string {
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
  }

  build() {
    Column() {
      if (this.videoUrl) {
        Video({
          src: this.videoUrl,
          currentProgressRate: 1.0,
          previewUri: '',
          controller: new VideoController()
        })
          .width('100%')
          .height(300)
          .autoPlay(false)
          .controls(true)
          .objectFit(ImageFit.Contain)
          .onStart(() => {
            console.info('Video onStart');
          })
          .onFinish(() => {
            console.info('Video onFinish');
            this.isPlaying = false;
          })
          .onError(() => {
            console.info('Video onError');
          });
      } else {
        Column() {
          Text('请选择视频文件')
            .fontSize(18)
            .fontColor(Color.Gray)
        }
        .width('100%')
        .height(300)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#F0F0F0')
      }

      Column() {
        Button('选择视频')
          .width('90%')
          .margin({ top: 20 })
          .onClick(() => {
            this.selectVideo();
          });

        if (this.videoUrl) {
          Row() {
            Button(this.isPlaying ? '暂停' : '播放')
              .width(100)
              .onClick(() => {
                this.togglePlay();
              });

            Button('停止')
              .width(100)
              .margin({ left: 10 })
              .onClick(async () => {
                await this.playerService.stop();
              });
          }
          .margin({ top: 20 });

          Row() {
            Text(this.formatTime(this.currentTime))
              .fontSize(14);

            Slider({
              value: this.currentTime,
              min: 0,
              max: this.duration > 0 ? this.duration : 100,
              step: 1,
              style: SliderStyle.OutSet
            })
              .width('60%')
              .margin({ left: 10, right: 10 })
              .blockColor('#007DFF')
              .trackColor('#E0E0E0')
              .selectedColor('#007DFF')
              .onChange((value: number) => {
                this.onSeekChange(value);
              });

            Text(this.formatTime(this.duration))
              .fontSize(14);
          }
          .margin({ top: 20, left: 20, right: 20 })
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween);
        }
      }
      .width('100%')
      .padding(20)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }
}
