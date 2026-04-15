# 当前实现状态

本文记录当前 ArkTS 版本播放器已落地的能力，以及仍需 AVPlayer / Native 内核升级支持的事项。

## 已落地

### P2 本地媒体库

- 通过系统视频选择器批量导入本地媒体，作为当前版本的媒体库扫描入口。
- 支持媒体库列表、最近播放、收藏列表和文件夹维度浏览。
- 支持展示媒体元数据，包括来源、文件夹、时长、播放进度、完成状态、最近播放时间和播放次数。
- 支持记住扫描过的目录，并在后续进行增量重扫。
- 支持清理失效的本地媒体条目，避免媒体库长期残留脏数据。

### P2 续播增强

- 打开带续播记录的视频时弹出继续播放提示。
- 播放完成后自动标记已完成，并清空续播位置。
- 历史记录按 `URI` 去重，并按最近播放时间排序。

### P3 网络播放

- 支持输入 `HTTP/HTTPS` 直链播放。
- 支持输入 `m3u8` 地址进行基础 HLS 播放。
- 为网络媒体增加基础弱网失败提示，并复用播放器重试入口。

### P3 远端协议栈

- 支持 WebDAV 浏览目录、鉴权下载到缓存并播放。
- 支持 FTP 浏览目录、下载到缓存并播放。
- 支持 DLNA 设备发现、投送、播放/暂停/停止、状态刷新、进度跳转和音量控制。
- 已支持 SMB 连接配置输入、配置保存、独立 Native bridge 和 `libsmb2` 依赖接入口。
- 已 vendoring `libsmb2` 上游源码；当构建环境可用时，当前 bridge 会进入真实 `connect/list/download-to-cache` 分支。

### P3 字幕与音轨

- 支持加载 `.srt` 外挂字幕。
- 支持字幕开关、偏移调整和文本渲染。
- 支持在 `AVPlayer` 路径下枚举并切换音轨。

### P4 播放器体验

- 支持在播放页手动切换横屏/竖屏。
- 支持画面比例切换、90 度旋转和更完整的媒体信息面板。
- 支持在画面区域通过滑动进行进度快调和音量快调，并提供快捷按钮兜底。
- 支持系统亮度联动、退出页面后恢复系统亮度。
- 支持 AVSession 后台播放与音频中断状态同步。

### P4 工程化

- 已提供 `pre-push` 自检脚本，覆盖文档快照、Native `cmake configure/build` 和关键源码存在性检查。
- 已接入 GitHub Actions CI，默认执行仓库级自检脚本。

### P4 播放内核升级准备

- 已抽象 `PlayerKernelService`，为当前 `Video` 内核和后续 `AVPlayer + Native` 内核切换预留能力描述。
- 在 UI 中增加当前内核状态与能力边界提示，避免后续扩展时混淆。
- 已接入 `AVPlayerService` 最小链路，支持通过 `XComponent` 获取 `surfaceId` 后播放当前媒体源。
- 当前页面已支持在 `ArkUI Video` 与 `AVPlayer` 两种内核之间切换，用于逐步迁移验证。
- Native 侧已补齐 `media_core` 分层骨架、NAPI 状态查询、事件回调和错误回传，桥接不再是纯 `Noop` stub。
- 当前 Native 侧已补齐 `FFmpeg Demuxer / Decoder / Resampler / Converter / Queue / Sync / Drain` 代码路径。
- 当前 Native 侧已补齐条件编译的 Harmony `NativeWindow renderer` 与 `OHAudio output` backend 接入位。
- 当前 Native 桥接会明确暴露 `backendName/blocker/stage/metrics`，用于标识真实软解内核的剩余阻塞点。

## 当前未落地

### P4 播放内核升级

以下事项需要切换到 `AVPlayer + XComponent` 或 Native 内核后推进：

- 更完整的格式兼容
- 软硬解策略
- 细粒度缓冲控制
- 更强的错误恢复与统计能力
- 外挂字幕真实渲染与多音轨真实切换
- 真正接入 `FFmpeg/libav*` 产物，打通平台音频输出、视频渲染与完整 `A/V sync`

### P5 VLC 风格扩展

以下扩展能力尚未实现：

- SMB / CIFS / NAS 真实浏览与播放
- 原生软解渲染闭环
- 均衡器

## 下一阶段建议

1. 接入 SMB / CIFS 客户端能力，补齐 NAS 浏览链路。
2. 接入 FFmpeg 或等效依赖，推进 Native 内核从骨架进入真实解码闭环。
3. 继续增强自动化回归与真机验证，覆盖 DLNA、媒体库增量重扫和 Native/SMB 桥接状态。
