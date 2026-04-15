# FFmpeg Integration Layout

将 HarmonyOS 可用的 FFmpeg 产物放到这里，`AppScope/entry/src/main/cpp/CMakeLists.txt`
会自动探测本目录下的头文件和库文件。

建议目录结构：

```text
third_party/ffmpeg/
├── include/
│   ├── libavcodec/
│   │   └── avcodec.h
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

当前仓库会检查：

- `include/libavcodec/avcodec.h`
- `lib/libavcodec.so`
- `lib/libavformat.so`
- `lib/libavutil.so`
- `lib/libswresample.so`
- `lib/libswscale.so`

说明：

- 如果目录完整，CMake 会定义 `PLAYER_SIRIUS_HAS_FFMPEG=1` 并链接这些库。
- 如果目录不完整，工程会继续构建，但 Native 播放后端会回落到占位实现，并在 UI 中显示 blocker。
- 当前仓库只完成了接入骨架，尚未实现真正的 `demux / decode / render / A/V sync`。
