# SMB 接入说明

本文说明 `Player Sirius` 当前的 `SMB / CIFS / NAS` 接入状态。

## 当前已完成

- 远端面板已支持 `SMB` 模式切换。
- 已支持输入 `host / port / share / username / password / path`。
- 已支持保存、读取和删除 SMB 连接配置。
- 已补齐 `SmbService` 能力声明与 `smb://` URI 构造逻辑。
- 已补齐独立 `smb_client_bridge` NAPI 模块和 `libsmb2` CMake 探测骨架。

## 当前 blocker

- 仓库中还没有接入 HarmonyOS 可用的 `libsmb2` Native 依赖。
- 因此当前 `SMB` 页面虽然已走到 Native bridge，但真实目录浏览和文件打开仍会返回明确 blocker。

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

1. 在 `smb_client_bridge.cpp` 中接入真实 `libsmb2` 会话
2. 接 `opendir/readdir/open/read/close`
3. 打通 SMB 文件下载到缓存
4. 再决定是否支持直接 SMB 流式读取
