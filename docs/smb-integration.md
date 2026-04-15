# SMB 接入说明

本文说明 `Player Sirius` 当前的 `SMB / CIFS / NAS` 接入状态。

## 当前已完成

- 远端面板已支持 `SMB` 模式切换。
- 已支持输入 `host / port / share / username / password / path`。
- 已支持保存、读取和删除 SMB 连接配置。
- 已补齐 `SmbService` 能力声明与 `smb://` URI 构造逻辑。
- 已补齐独立 `smb_client_bridge` NAPI 模块和 `libsmb2` CMake 探测骨架。
- 在检测到 `libsmb2` 后，bridge 现在会进入真实 `connect -> listDirectory -> downloadToCache` 分支。
- 已 vendoring `libsmb2` 上游源码到 `third_party/libsmb2/upstream`，构建时优先从源码编译。

## 当前 blocker

- 仓库中还没有接入 HarmonyOS 可用的 `libsmb2` Native 依赖。
- 因此当前 `SMB` 页面虽然已走到 Native bridge，但真实目录浏览和文件打开仍会返回明确 blocker。
- 当前环境也没有 `libsmb2` 头文件和动态库，所以本次实现还没有经过编译级验证。

## 目录约定

当前优先使用 vendored 源码：

```text
third_party/libsmb2/
├── upstream/
│   ├── CMakeLists.txt
│   ├── include/
│   └── lib/
├── include/
└── lib/
```

只有在 `upstream/` 不存在时，才会退回 `include/ + lib/` 的预编译产物模式。

## 下一步

1. 在真机构建环境中编译并校准 vendored `libsmb2`
2. 校验 `smb_client_bridge.cpp` 与目标平台头文件/符号完全对齐
3. 打通 SMB 文件下载到缓存后的播放回归
4. 再决定是否支持直接 SMB 流式读取
