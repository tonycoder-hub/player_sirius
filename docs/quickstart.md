# 开发 Quickstart

本文用于初始化 `Player Sirius` 的 HarmonyOS 开发环境。当前仓库已经包含 ArkTS Stage Model 工程骨架，DevEco Studio 应打开仓库根目录，并通过根目录 `build-profile.json5` 识别 `AppScope/entry` 模块。

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

## 5. 打开现有工程

当前工程已经落在仓库内，建议按以下步骤打开：

1. 用 DevEco Studio 打开仓库根目录，而不是 `AppScope` 或 `AppScope/entry` 子目录。
2. 等待 IDE 完成 Sync，确认 Project 视图或运行配置中出现 `entry` 模块。
3. 如果本机 SDK 位置不同，更新未提交的 `local.properties`。
4. 首次打开后由 IDE 重新生成 `.idea/`、`.hvigor/`、`build/` 等本机缓存。
5. 执行 Build / Run，优先使用真机验证 Native、音频焦点和后台播放相关能力。

如果 DevEco Studio 没有显示 `entry`：

1. 确认打开的是仓库根目录。
2. 关闭 DevEco Studio 后删除本机生成的 `.idea/` 与 `.hvigor/` 缓存目录，再重新打开仓库根目录并执行 Sync。
3. 确认根目录 `build-profile.json5` 中存在 `modules[].name = "entry"`，且 `srcPath` 指向 `./AppScope/entry`。
4. 确认 `AppScope/entry/src/main/module.json5` 中 `module.type` 为 `entry`。
5. 如果报 `The target can not be empty`，确认 `AppScope/entry/build-profile.json5` 中存在 `targets[].name = "default"`。
6. 不要提交 `.idea/` 与 `.hvigor/`，这些目录是本机 IDE/构建缓存，可能让其他工作区复用旧的模块识别结果。

## 6. 初始化后的建议目录

工程创建完成后，优先整理成下面的结构：

```text
.
├── AppScope/
│   ├── app.json5
│   └── entry/               # ArkUI 页面、应用入口与 Native bridge
├── docs/
├── scripts/
├── third_party/
├── build-profile.json5
├── hvigorfile.ts
└── oh-package.json5
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

- 优先完成 SMB/NAS 真机联调。
- 接着接入 FFmpeg 产物和目标平台 Native 输出 backend。
- 最后补齐协议栈、媒体库和真机回归体系，逐步把功能往 VLC 对齐。
