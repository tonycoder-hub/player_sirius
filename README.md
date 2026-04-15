# Player Sirius

面向 HarmonyOS 的多媒体播放器工程，目标是在鸿蒙设备上逐步对齐 VLC 的核心能力，优先覆盖本地播放、网络流媒体、字幕、多音轨、播放控制和媒体库管理等高频场景。

## 目标

- 支持常见本地与远程媒体格式播放，覆盖点播、直播、在线播放等场景。
- 兼顾手机、平板、智慧屏等 HarmonyOS 设备形态，统一核心播放能力。
- 在 ArkUI 侧提供现代化交互，在 Native 侧提供稳定的解封装、解码、渲染与同步能力。
- 采用可替换的播放内核设计，便于后续接入硬解、软件解码、外挂字幕和更多协议栈。

## 非目标

- 首个版本不追求完整复刻 VLC 的全部桌面高级能力。
- 首个版本暂不覆盖编辑、转码、投屏中继、DLNA Server 等复杂功能。
- 首个版本不把 UI 皮肤系统作为重点，先保证播放稳定性与兼容性。

## 系统设计

### 1. 分层架构

1. 应用层（ArkUI / ArkTS）
   - 页面与路由：首页、媒体库、播放页、设置页、调试页。
   - 交互能力：手势控制、倍速、进度拖拽、选轨、字幕切换、播放列表。
   - 状态管理：统一管理当前媒体、播放状态、历史记录、收藏、最近播放。

2. 播放控制层（ArkTS Service）
   - 对外提供统一的 `PlayerFacade`，屏蔽不同播放引擎差异。
   - 负责会话管理、生命周期、后台播放、音频焦点、错误恢复、配置持久化。
   - 编排 UI 与 Native Core 的通信，包括播放指令、事件订阅、统计信息回传。

3. 播放内核层（Native C/C++）
   - 包含 demux、decoder、renderer、A/V sync、subtitle pipeline。
   - 优先定义抽象接口，支持后续在软解与硬解之间切换。
   - 网络协议、缓存策略、时钟同步、音视频缓冲控制尽量留在该层。

4. 平台适配层
   - 对接 HarmonyOS 音频输出、窗口渲染、文件系统、网络、权限、后台任务。
   - 封装设备能力差异，例如前后台切换、耳机事件、屏幕旋转和多窗口。

### 2. 核心模块

- `app_shell`
  - 承载 ArkUI 页面、导航、主题和用户交互。
- `player_service`
  - 负责播放器会话、命令分发、状态同步和恢复策略。
- `media_core`
  - 负责解封装、解码、字幕渲染、时钟同步和 buffer 管理。
- `media_source`
  - 统一本地文件、HTTP/HTTPS、HLS、后续 SMB/WebDAV/FTP 等数据源。
- `media_library`
  - 管理扫描索引、历史播放、收藏、最近访问和元数据缓存。
- `diagnostics`
  - 采集日志、播放指标、崩溃现场、卡顿与首帧耗时数据。

### 3. 关键技术决策

- UI 技术栈：ArkUI + ArkTS，采用 Stage Model。
- 核心播放：建议以 Native C/C++ 为主，ArkTS 只负责控制面与页面编排。
- 解码策略：优先预留软解和系统硬解双通路，方便后续按机型能力切换。
- 字幕能力：从外置字幕、内嵌字幕、样式控制开始，逐步补齐字幕偏移与编码检测。
- 插件化扩展：媒体源、解码器、渲染器尽量做成边界清晰的可替换模块。
- 许可证审查：若引入 FFmpeg、libass 或 VLC 相关实现，需要提前审查 LGPL/GPL 约束。

### 4. 推荐目录规划

```text
.
├── README.md
├── docs/
│   └── quickstart.md
├── apps/
│   └── player_app/          # ArkUI 主应用
├── modules/
│   ├── player_service/      # ArkTS 控制层
│   ├── media_library/       # 媒体库与索引
│   └── diagnostics/         # 日志与指标
├── native/
│   ├── media_core/          # C/C++ 播放内核
│   ├── adapters/            # HarmonyOS 能力适配
│   └── third_party/         # FFmpeg/libass 等三方依赖
└── scripts/
    ├── setup/
    └── toolchains/
```

### 5. 关键播放链路

1. UI 选择媒体源并创建播放会话。
2. `player_service` 根据 URL 或文件类型选择数据源适配器。
3. `media_core` 完成探测、解封装、解码、A/V sync 和字幕渲染。
4. 平台适配层输出音频和视频帧，并回传播放状态、统计信息和错误。
5. `player_service` 更新状态存储，驱动 UI 与历史记录同步。

### 6. 对齐 VLC 的能力路线

#### Phase 0: 基础工程

- 完成 HarmonyOS 工程初始化、构建链路、日志链路和 Native 模块接入。
- 打通本地 MP4/H.264/AAC 的基本播放与暂停、拖拽、倍速能力。

#### Phase 1: 核心播放

- 支持常见容器与编码格式。
- 补齐音轨切换、字幕切换、播放列表、后台音频播放。
- 支持 HTTP/HTTPS 和 HLS 流媒体播放。

#### Phase 2: 媒体库与稳定性

- 增加目录扫描、历史记录、收藏、缩略图和元数据缓存。
- 加强异常恢复、弱网缓存、首帧优化、卡顿监控与崩溃治理。

#### Phase 3: 高级能力

- 扩展 SMB/WebDAV/FTP/NAS 访问。
- 增加硬解策略、字幕样式增强、画面比例、音频均衡器等增强功能。

## 近期落地建议

- 先创建一个最小可运行的 ArkUI Stage 工程。
- 同步创建 `native/media_core` 占位模块，尽早打通 ArkTS 到 Native 的调用链。
- 用少量稳定样本媒体建立回归集合，优先验证首帧、拖拽、切后台恢复。
- 先定义播放器状态机和错误码，再逐步补协议、字幕和媒体库功能。

## 当前实现状态

### 已实现

- 本地视频播放、网络直链播放、HLS 基础播放。
- 外挂字幕 `.srt` 选择、解析、渲染、开关和偏移。
- `AVPlayer` 多音轨枚举与切换。
- 后台播放、音频焦点中断处理、耳机/抢占场景下的暂停恢复。
- 缓冲状态、首帧耗时、弱网卡顿检测与自动重试。
- 自动/手动播放内核选择，以及 `ArkUI Video` / `AVPlayer` / `Native Bridge` 之间的失败回退。
- WebDAV、FTP 的目录浏览与缓存后播放。
- DLNA 设备发现、URL 投送与 `Play/Pause/Stop`、状态刷新、进度跳转、音量控制。
- 媒体库导入、文件夹筛选、缩略图缓存、基础元数据缓存、扫描目录记忆、增量重扫、失效清理。
- 左侧亮度手势、右侧音量手势、横向进度快调。
- 更完整的媒体信息面板，支持显示文件大小、进度、内核/桥接状态、缓冲统计和远端协议摘要。
- `pre-push` 自检脚本与 GitHub Actions CI，默认执行文档快照和 Native `cmake configure/build` 检查。

### 已知限制

- `WebDAV`、`FTP` 当前采用“下载到缓存后播放”，不是完整的远端流式播放实现。
- `DLNA` 投屏目前仍偏基础控制版，没有做状态订阅、完整设备兼容适配和长期稳定性治理。
- 本地/缓存媒体投屏依赖应用内本地 HTTP 服务，设备必须能访问手机/平板的局域网地址。
- 媒体库目录扫描当前优先尝试文件夹选择能力；若设备不支持，会回退到批量选择视频导入。
- 弱网恢复当前以自动重试和基础缓冲指标为主，还没有完整 ABR/多级退避策略。

### 必须继续补的部分

- **Native 播放内核本体**
  - 当前已经有 ArkTS 桥接服务和 `cpp/NAPI` 主控制链。
  - 当前已补齐 `media_core` 分层、`Demuxer / Decoder / AudioResampler / VideoConverter / packet-frame queue / playback worker / drain / sync-controller` 代码路径。
  - 当前已补齐条件编译的 Harmony `NativeWindow renderer` 与 `OHAudio output` backend 接入位。
  - Native 桥接已支持更细的 `stage / metrics / queue depth / audio clock / video clock / completed` 状态透传。
  - 但仓库内仍未放入可用的 `FFmpeg/libav*` 产物，且当前环境没有 Harmony `native_window/ohaudio` 头文件与库，所以这些真实 backend 还未被启用。
  - 现阶段更准确的状态是“FFmpeg Native 内核主体代码已写入仓库，但仍受外部依赖约束”，不是“Native 播放器已完整可用”。

- **SMB / CIFS**
  - 当前已补齐 `SMB` 面板、配置保存、服务接口、独立 `smb_client_bridge`，并 vendoring 了 `libsmb2` 上游源码。
  - 构建时会优先尝试从 `third_party/libsmb2/upstream` 编译，再退回到预编译 `include/lib` 模式。
  - 真实 `connect / list / download-to-cache` 分支已经写入 bridge，且本机已完成编译级验证。
  - 当前仍缺目标平台运行级验证与完整 NAS 联调。

- **更完整的工程化能力**
  - 媒体库仍缺少目录变更监听、增量索引和更完整的元数据抽取。
  - 投屏仍缺少完整会话管理、状态同步和失败恢复。
  - 当前已有脚本化检查和 CI，但仍缺完整单元测试、协议栈回归和真机回归体系。

## 发布判断建议

### 可以对外说明“已支持”的能力

- 本地播放
- HTTP/HTTPS/HLS 基础播放
- 外挂字幕
- 多音轨切换
- 后台播放与音频焦点
- WebDAV / FTP 访问与播放
- DLNA 基础投屏
- 媒体库导入、缩略图和基础管理
- 亮度/音量/进度手势

### 不建议对外宣称“已完整完成”的能力

- 完整 Native 播放内核
- 纯 SMB/CIFS 访问
- 完整 NAS 协议覆盖
- 完整投屏会话系统
- 完整自动化回归体系
