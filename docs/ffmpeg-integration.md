# FFmpeg 接入说明

本文说明 `Player Sirius` 当前 Native 软解链路如何接入 FFmpeg。

## 当前状态

- `media_core` 已具备 Native 内核分层、能力描述、状态查询和事件回调。
- 当前 pipeline 已拆成 `demuxer / decoder / renderer / audio-output / clock` 五段式骨架，并能向 UI 暴露当前 `stage`。
- Native 统计事件已包含基础 metrics，如 `bufferedDurationMs`、`decodedVideoFrames`、`renderedVideoFrames` 和 `emittedEvents`。
- `native_player_bridge` 已能向 ArkTS 暴露：
  - `getCapability()`
  - `getState()`
  - `setEventListener()`
  - `prepare()/play()/pause()/stop()/seek()/release()`
- 当前真正缺少的是 FFmpeg 二进制和实际解码管线实现。

## 目录约定

按以下目录放置 FFmpeg 产物：

```text
third_party/ffmpeg/
├── include/
│   ├── libavcodec/
│   ├── libavformat/
│   ├── libavutil/
│   ├── libswresample/
│   └── libswscale/
└── lib/
    ├── libavcodec.so
    ├── libavformat.so
    ├── libavutil.so
    ├── libswresample.so
    └── libswscale.so
```

## CMake 行为

`AppScope/entry/src/main/cpp/CMakeLists.txt` 会：

1. 从仓库根目录定位 `third_party/ffmpeg`
2. 自动探测 FFmpeg 头文件和 `.so`
3. 在探测成功时定义 `PLAYER_SIRIUS_HAS_FFMPEG=1`
4. 在探测失败时继续使用占位后端

## 当前 blocker

- 即使检测到了 FFmpeg，当前仓库也还没有把 `avformat_open_input`、`avcodec_send_packet`、
  `avcodec_receive_frame`、音频重采样、视频渲染和时钟同步真正串起来。
- 当前若切到 Native 路径，UI 已能区分是卡在 `input / demuxer / decoder / renderer / playback-loop`
  哪个阶段，并能看到基础缓冲/帧统计，但这些阶段还没有真实媒体数据流。
- 因此当前 UI 上看到的 Native 后端状态可能是：
  - `ffmpeg-placeholder`：仓库里还没放 FFmpeg 产物
  - `ffmpeg-linked`：已检测到 FFmpeg，但真实播放管线仍未实现

## 下一步实现顺序

1. 接 `avformat` 打开输入和流探测
2. 接 `avcodec` 完成视频/音频解码
3. 接音频输出与视频帧渲染
4. 补 A/V sync 和时间轴推进
5. 再把 `capability.available` 切为 `true`
