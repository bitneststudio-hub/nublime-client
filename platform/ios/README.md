# iOS 平台（原生侧）

| 项 | 值 |
|---|---|
| 隧道核心 | `NEPacketTunnelProvider` + Xray（需 gomobile 打成静态库/XCframework，**工作量最大**） |
| 分发 | App Store（审核对 VPN 类目要求：必须声明用途、不得绕过地区限制） |
| Flutter 平台目录 | `app/ios/`（Flutter 默认模板） |
| 安装包 | `installer/ios/`（TestFlight / App Store） |
| 技术设计 | 待产出 |

## 已知约束

- iOS 扩展进程有 **严格内存上限**（通常 ~15MB 级别，视设备而定），Xray 的 geo 数据加载策略要重新设计
- 必须使用 NetworkExtension entitlement，且 App Store 审核会检查"是否真的需要 VPN"
- 无法像 Android 那样动态加载内核 → 核心必须静态链接进扩展
