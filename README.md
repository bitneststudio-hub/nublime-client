# WildLime VPN

开源、多平台的 VPN 客户端。Flutter 共享一套 UI 与业务层，每个平台只实现自己的"隧道核心 + 系统集成"。

- 后端与节点：`www.nublime.com`（Xray-core，VLESS + REALITY + Vision）
- 商业运营：BitNest Studio（NZ）
- 本仓库 = 客户端 + 各平台构建/安装脚本 + 技术文档；**不含后端、不含节点凭据**

## 目录结构

```
.
├── app/                    唯一 Flutter 工程（共享 lib/ + 5 个平台目录）
│   ├── lib/                共享业务层：UI、状态机、API、配置转换（唯一碰撞面）
│   ├── android/  windows/  linux/  macos/  ios/
│   ├── assets/  test/  web/
│   └── pubspec.yaml
├── platform/               各平台原生侧（非 Dart）：说明、桥接约定、运行时核心
│   ├── windows/  linux/  macos/  ios/
├── tools/                  构建与开发脚本
│   ├── common/             sing-box → Xray 配置生成器（全平台共用）
│   ├── windows/  linux/  macos/  ios/
│   └── dev/                worktree 等并行开发辅助
├── installer/              安装包脚本
│   ├── windows/  linux/  macos/  ios/
├── docs/
│   ├── techdesign/         每平台技术设计说明书
│   ├── prompts/            各 session 的开工 prompt
│   └── evidence/           审计与验收证据归档
├── LICENSE
└── NOTICE
```

## 平台状态

| 平台 | 状态 | 核心技术 | 版本 |
|---|---|---|---|
| Android | ✅ 已发布 | Xray VpnService + libXray(AAR) | 4.1.41 |
| Windows | 🚧 W0 验证中 | xray.exe 子进程 + Wintun | — |
| Linux | 📐 设计阶段 | xray 子进程 + tun（CAP_NET_ADMIN） | — |
| macOS | ⏳ 未开始 | NEPacketTunnelProvider（utun） | — |
| iOS | ⏳ 未开始 | NEPacketTunnelProvider + Xray 静态库 | — |

## 快速开始

```bash
# Android（唯一已验证可构建的平台）
cd app
flutter pub get
flutter build apk --release --target-platform android-arm64

# 其它平台：见 platform/<os>/README.md，构建前需要先放运行时核心
```

## 并行开发

多个 session / 多个平台会同时开工。**动手前先读 [`PLATFORMS.md`](PLATFORMS.md)** —— 里面定义了目录归属、
共享层的修改纪律、以及 git worktree 的用法。违反它会直接造成冲突。

## 许可

见 `LICENSE`。第三方组件（Xray-core MPL-2.0、Wintun 预编译二进制许可）见 `NOTICE`。

## Attribution

Parts of this program are derived from hiddify-app by the Hiddify team
(https://github.com/hiddify/hiddify-app), version v4.1.2 (commit 54bc7eeb).
Original license: https://github.com/hiddify/hiddify-app/blob/v4.1.2/LICENSE.md

Modified by BitNest Studio, March-November 2026. A summary of changes is in
CHANGES-FROM-UPSTREAM.md.

This program, as distributed by BitNest Studio, is licensed under the GNU General
Public License version 3 (see LICENSE). For the parts derived from hiddify-app, the
following additional terms under GPLv3 section 7 apply: attribution to Hiddify must be
preserved; modified versions must be marked as different from the original; the
Hiddify name and logos may not be used to name or promote derived works.

Third-party components and their licenses are listed in NOTICE.

## Source code

This repository publishes the complete source code for the client (`SOURCE.md`),
the build instructions (`BUILD.md`) and all third-party notices (`NOTICE`).
