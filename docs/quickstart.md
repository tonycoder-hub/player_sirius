# 开发 Quickstart

本文用于初始化 `Player Sirius` 的 HarmonyOS 开发环境。当前仓库还没有生成正式工程，因此这里先约定工具链、SDK 组件和最小启动流程，后续创建工程时直接按本文执行即可。

## 1. 推荐环境

- 操作系统：Linux 或 macOS 开发机，Windows 也可使用 DevEco Studio。
- IDE：DevEco Studio 最新稳定版。
- 语言栈：ArkTS + ArkUI（应用层），C/C++（播放内核）。
- 构建工具：`hvigor`、`ohpm`。
- 调试工具：`hdc`、DevEco Studio Log 面板。

## 2. 必装 SDK / 工具链

建议在 DevEco Studio 的 SDK Manager 中至少安装以下组件：

- HarmonyOS SDK
  - ArkTS/ArkUI 所需的基础 SDK。
- Native SDK
  - 用于构建 `media_core` 这类 C/C++ 模块。
- Command Line Tools
  - 便于在终端里使用 `hvigor`、`hdc` 等命令。
- Emulator Image
  - 可选，但播放器项目更建议优先使用真机调试。
- CMake / Ninja
  - 若 Native 模块使用 CMake 构建，需要一并安装。

如果后续引入第三方播放栈，还需要准备：

- FFmpeg 交叉编译产物或 HarmonyOS 适配版本。
- `libass` 等字幕库。
- 可能的网络与安全依赖，例如 `openssl`。

## 3. 建议的本机环境变量

不同开发机安装路径不一样，下面以 `${DEVECO_HOME}` 和 `${HARMONY_SDK_HOME}` 表示你的实际路径。

```bash
export DEVECO_HOME="$HOME/DevEcoStudio"
export HARMONY_SDK_HOME="$HOME/Huawei/Sdk"
export JAVA_HOME="$DEVECO_HOME/jbr"
export NODE_HOME="$DEVECO_HOME/tools/node"

export PATH="$JAVA_HOME/bin:$PATH"
export PATH="$NODE_HOME/bin:$PATH"
export PATH="$HARMONY_SDK_HOME/toolchains:$PATH"
export PATH="$HARMONY_SDK_HOME/command-line-tools/hdc:$PATH"
export PATH="$HARMONY_SDK_HOME/command-line-tools/hvigor/bin:$PATH"
export PATH="$HARMONY_SDK_HOME/command-line-tools/ohpm/bin:$PATH"
```

说明：

- 实际目录名称以 DevEco Studio 安装结果为准。
- 如果 `hvigor`、`ohpm`、`hdc` 已由 IDE 自动配置，可不重复手工维护。
- 建议把上述配置写入 `~/.bashrc` 或 `~/.zshrc`。

## 4. 环境自检

安装后先确认以下命令可用：

```bash
java -version
node -v
ohpm -v
hdc version
```

如果项目生成后带有 `hvigorw`，再执行：

```bash
./hvigorw -v
```

## 5. 初始化工程的推荐方式

当前仓库没有现成工程，建议按以下步骤初始化：

1. 用 DevEco Studio 新建一个 ArkTS Stage Model 应用。
2. 应用名建议使用 `player_sirius`，包名使用公司或组织域名反写形式。
3. Compatible SDK 选择团队统一版本，建议从当前稳定 API 起步。
4. 创建完成后，把 IDE 生成的主工程提交到当前仓库根目录。
5. 立刻补充一个 Native 模块，用于承载后续的 `media_core`。

## 6. 初始化后的建议目录

工程创建完成后，优先整理成下面的结构：

```text
.
├── AppScope/
├── entry/                   # ArkUI 页面与应用入口
├── modules/
│   ├── player_service/
│   └── media_library/
├── native/
│   ├── media_core/
│   └── adapters/
├── docs/
└── hvigor/
```

## 7. 首次跑通最小链路

建议按下面顺序落地：

1. 跑通空白 ArkUI 页面并能安装到真机。
2. 在 `player_service` 中定义播放器状态机与事件模型。
3. 在 `native/media_core` 中提供一个最小桥接接口，例如 `open / play / pause / seek / stop`。
4. 从本地 MP4 文件开始验证播放链路，再扩展到 HTTP/HLS。
5. 为播放页增加日志面板或调试浮层，方便观察首帧时间、buffer 状态和错误码。

## 8. 设备与调试建议

- 真机优先：播放器涉及解码、音频焦点、前后台切换，模拟器覆盖不完整。
- 样本优先：准备一组固定测试媒体，包括 MP4、MKV、HLS、外挂字幕和多音轨文件。
- 日志分层：ArkTS 控制层与 Native 内核分开打点，便于定位卡顿和崩溃。
- 早做回归：每新增一种媒体协议或解码器，都应补一条最小回归样本。

## 9. 下一步建议

- 先让仓库生成一个最小 HarmonyOS 工程骨架。
- 接着增加 Native 模块和 ArkTS 到 Native 的桥接。
- 最后再引入 FFmpeg、字幕库和网络协议能力，逐步把功能往 VLC 对齐。
