# SMB 接入说明

本文说明 `Player Sirius` 当前的 `SMB / CIFS / NAS` 接入状态。

## 当前已完成

- 远端面板已支持 `SMB` 模式切换。
- 已支持输入 `host / port / share / username / password / path`。
- 已支持保存、读取和删除 SMB 连接配置。
- 已补齐 `SmbService` 能力声明与 `smb://` URI 构造逻辑。
- 已补齐独立 `smb_client_bridge` NAPI 模块和 `libsmb2` CMake 探测骨架。
- 在检测到 `libsmb2` 后，bridge 现在会进入真实 `connect -> listDirectory -> downloadToCache` 分支。

## 当前 blocker

- 仓库中还没有接入 HarmonyOS 可用的 `libsmb2` Native 依赖。
- 因此当前 `SMB` 页面虽然已走到 Native bridge，但真实目录浏览和文件打开仍会返回明确 blocker。
- 当前环境也没有 `libsmb2` 头文件和动态库，所以本次实现还没有经过编译级验证。

## 目录约定

请将 `libsmb2` 产物放到：

```text
third_party/libsmb2/
├── include/
│   └── smb2/
│       └── smb2.h
└── lib/
    └── libsmb2.so
```

## 下一步

1. 将 `third_party/libsmb2` 中放入可用头文件和 `libsmb2.so`
2. 在真机构建上校准 `libsmb2` 的具体符号/结构字段
3. 打通 SMB 文件下载到缓存后的播放回归
4. 再决定是否支持直接 SMB 流式读取
