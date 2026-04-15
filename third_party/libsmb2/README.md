# libsmb2 Integration Layout

当前仓库已经 vendoring 了 `libsmb2` 上游源码到 `third_party/libsmb2/upstream`，
`AppScope/entry/src/main/cpp/CMakeLists.txt` 会优先使用源码构建。

建议目录结构：

```text
third_party/libsmb2/
├── README.md
├── upstream/
│   ├── CMakeLists.txt
│   ├── include/
│   └── lib/
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
- vendored `libsmb2` 上游源码，构建时优先走源码编译

当前仓库尚未完成：

- 真机构建校准与编译验证
- 目录浏览、文件下载的真机回归
- SMB 会话错误恢复与断线重连
