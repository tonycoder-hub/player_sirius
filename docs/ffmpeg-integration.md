# FFmpeg 接入说明

本文说明 `Player Sirius` 当前 Native 软解链路如何接入 FFmpeg。

## 当前状态

- `media_core` 已具备 Native 内核分层、能力描述、状态查询和事件回调。
- 当前 pipeline 已拆成 `demuxer / decoder / renderer / audio-output / clock` 五段式骨架，并能向 UI 暴露当前 `stage`。
- Native 统计事件已包含基础 metrics，如 `bufferedDurationMs`、`decodedVideoFrames`、`renderedVideoFrames` 和 `emittedEvents`。
- 已补齐基于 `FFmpeg` 的 `Demuxer / Decoder / AudioResampler / VideoConverter / packet-frame queue / playback worker / drain / sync-controller` 代码路径。
- 已新增 Harmony 侧条件编译的 `NativeWindow renderer` 与 `OHAudio output` backend 接入位。
- `native_player_bridge` 已能向 ArkTS 暴露：
  - `getCapability()`
  - `getState()`
  - `setEventListener()`
  - `prepare()/play()/pause()/stop()/seek()/release()`
- 当前真正缺少的是 FFmpeg 二进制，以及真实平台音频输出和视频渲染输出。

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
4. 探测 Harmony `native_window/ohaudio` 头文件与库
5. 在探测失败时继续使用占位后端

## 当前 blocker

- 当前若切到 Native 路径，代码已具备真实 `demux / decode / resample / convert / queue / sync / drain` 结构。
- 但仓库中还没有实际 `third_party/ffmpeg` 产物，因此当前编译仍会回退到 placeholder backend。
- 即使 FFmpeg 产物到位，当前也仍依赖目标平台提供 Harmony `native_window/ohaudio` 头文件与库，才能启用真实平台输出 backend。
- 因此当前 UI 上看到的 Native 后端状态可能是：
  - `ffmpeg-placeholder`：仓库里还没放 FFmpeg 产物
  - `ffmpeg-linked`：已检测到 FFmpeg，且会进入真实 demux/decode 管线；若平台输出库缺失，则仍退回内存 sink

## 下一步实现顺序

1. 放入 `third_party/ffmpeg` 头文件与库
2. 在目标环境提供 `native_window/ohaudio` 头文件与库
3. 让平台输出 backend 在目标工具链下完成首次真实编译
4. 完善 seek、drain 和完成态事件流
5. 再把 `capability.available` 切为 `true`
