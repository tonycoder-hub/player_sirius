# libsmb2 Integration Layout

将 HarmonyOS 可用的 `libsmb2` 头文件和动态库放到这里，后续即可继续把 `SMB/NAS`
浏览与下载链路从占位实现切换成真实 Native 能力。

建议目录结构：

```text
third_party/libsmb2/
├── include/
│   └── smb2/
│       └── smb2.h
└── lib/
    └── libsmb2.so
```

当前仓库已经完成：

- ArkTS 侧 `SMB` 配置输入、配置保存和远端面板 UI
- `SmbService` 能力声明与 `smb://` URI 构造
- `StorageService` 中的 SMB profile 持久化
- 独立 `smb_client_bridge` NAPI 模块和 `libsmb2` CMake 探测骨架
- `libsmb2` 存在时的真实 `connect/list/download-to-cache` 分支

当前仓库尚未完成：

- 真实 `libsmb2` Native bridge
- 目录浏览、文件下载和媒体直读
- SMB 会话鉴权与错误恢复
