# 多平台并行开发规则

> 目的：让 Windows / Linux / macOS / iOS / Android 五条线能同时开工而不互相踩踏。

## 1. 唯一硬约束：Flutter 的共享层只有一个

五个平台共用 **同一份 `app/lib/`**（UI、状态机、API 客户端、配置转换器）。这是**唯一会真正撞车的地方**。
平台目录（`app/android/`、`app/windows/`……）天然互不影响，随便并行。

推论：
- 各平台可以**同时**改自己的平台目录、自己的 `tools/<os>/`、`installer/<os>/`、`platform/<os>/` —— 零冲突。
- **改 `app/lib/` 里已存在的文件** = 高危操作，必须先说清楚再动。

## 2. 目录归属

| 路径 | 谁能改 | 说明 |
|---|---|---|
| `app/lib/**` | 所有人，但**必须先在 PLATFORMS.md 末尾登记** | 共享层；改动要能被其它平台编译 |
| `app/android/**` | Android 线 | |
| `app/windows/**` | Windows 线 | |
| `app/linux/**` | Linux 线 | |
| `app/macos/**` `app/ios/**` | 各自平台线 | |
| `platform/<os>/**` | 对应平台线 | 原生侧说明与桥接约定 |
| `tools/<os>/**` | 对应平台线 | |
| `tools/common/**` | 所有人，改前登记 | 配置生成器，全平台共用 |
| `installer/<os>/**` | 对应平台线 | |
| `docs/techdesign/<os>-*.md` | 对应平台线 | |
| `docs/evidence/**` | 追加式，不删别人的 | 审计证据 |
| `app/pubspec.yaml` | 只在主 session 改 | 加依赖会影响所有平台 |

## 3. 推荐做法：每个平台一个 git worktree

同一仓库、不同分支、**不同工作目录**，物理上就不可能互相覆盖：

```bash
tools/dev/new-worktree.sh windows     # 生成 ../wildlime-windows （分支 platform/windows）
tools/dev/new-worktree.sh linux
tools/dev/new-worktree.sh macos
tools/dev/new-worktree.sh ios
```

每个 session 在自己的 worktree 里干活，完成后 rebase 到 main 再合并。
这样即使两个 session 同时改 `app/pubspec.yaml`，也不会互相丢改动（会以冲突形式暴露出来，而不是静默覆盖）。

## 4. 分支与提交前缀

| 平台 | 分支 | 提交前缀 |
|---|---|---|
| Android | `main` 或 `android/*` | `android:` |
| Windows | `platform/windows` | `windows:` |
| Linux | `platform/linux` | `linux:` |
| macOS | `platform/macos` | `macos:` |
| iOS | `platform/ios` | `ios:` |
| 共享/工具 | — | `common:` |

## 5. 共享层改动登记（追加到本文件末尾）

格式：`- YYYY-MM-DD · <平台> · <文件> · <改动> · <影响面>`

- 2026-11-01 · Android · `lib/features/per_app_proxy/overview/per_app_proxy_page.dart` · 加 include 模式空名单提示条 · 仅 Android 分应用页，其它平台不引用
- 2026-11-02 · 共享/隐私 · `lib/core/analytics/analytics_controller.dart`、`lib/bootstrap.dart` · 遥测默认关闭：新增 `kEnableTelemetry`（编译期，默认 false）+ 偏好默认 false + 空 DSN/非移动端不 init；Windows 不包 `SentryUserInteractionWidget` · 全平台；设置页开关行为不变（默认显示关），Android 回归 124 测试全绿
- 2026-11-02 · 共享/测试 · `test/b3_dynamic_node_test.dart` · 静态门 allowlist 增加 Windows tun 常量 `10.9.0.1`/`128.0.0.0` · 仅测试门
