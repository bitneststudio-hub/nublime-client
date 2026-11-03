# tools/windows —— Windows 构建与运维脚本

| 文件 | 用途 |
|---|---|
| `fetch_core.ps1` | 从官方 release 拉 Xray-core v26.7.11 到 `app/windows/core/`（xray.exe + wintun.dll + geo 数据 + 许可） |
| `build.ps1` | `flutter build windows --release` → 拷贝核心 → 出 zip + sha256（待放到本目录） |

配置生成器已移到共用目录：`tools/common/make_xray_config.py`（五个平台共用）。

运行时核心二进制**不入库**（`.gitignore` 已排除），换机器先跑 `fetch_core.ps1`。
