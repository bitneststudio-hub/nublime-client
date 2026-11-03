# macOS 平台（原生侧）

| 项 | 值 |
|---|---|
| 隧道核心 | Xray 核心 + **utun**（NetworkExtension `NEPacketTunnelProvider`） |
| 分发要求 | 需要 Apple Developer Program（Developer ID + notarization）；NE entitlement 由 Apple 审批 |
| Flutter 平台目录 | `app/macos/`（Flutter 默认模板，未接核心） |
| 安装包 | `installer/macos/`（.pkg / DMG） |
| 技术设计 | 待产出 |

## 已知约束

- 系统级 VPN（非 App Store 分发）需要 `com.apple.developer.networking.networkextension` 权限，
  申请周期以周计 —— **这是排期的最大不确定性，不是技术难点**
- 沙箱 + 签名 + 公证三段流水线缺一不可，否则用户首次打开会被 Gatekeeper 拦
- 共享 UI 可直接复用（`app/lib/`），窗口是桌面尺寸，不走手机布局
