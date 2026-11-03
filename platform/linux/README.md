# Linux 平台（原生侧）

| 项 | 值 |
|---|---|
| 隧道核心 | 官方 `xray` 二进制子进程（`tun` inbound 原生支持 Linux） |
| 权限 | 需要 root 或 `CAP_NET_ADMIN`（`setcap` 或 systemd service，**未定**） |
| DNS | `systemd-resolved` 的 stub（127.0.0.53）与 tun 的冲突待解 |
| Flutter 平台目录 | `app/linux/`（Flutter 默认模板，未接核心） |
| 构建脚本 | `tools/linux/`（待建） |
| 安装包 | `installer/linux/`（.deb / AppImage 优先级待定） |
| 技术设计 | `docs/techdesign/`（待产出：WildLime_Linux_TechDesign_v1.md） |

## 复用

配置生成器全平台共用：`tools/common/make_xray_config.py --tun-name WildLime`，
产出的配置与 Windows 完全相同（Xray 的 tun inbound 在两个平台上字段一致）。

## 待回答（设计阶段必须先定）

1. 权限模型：root 直跑 / `setcap cap_net_admin+ep` / systemd service + PolicyKit
2. DNS 接管方式（`resolvectl dns <if>` vs 关闭 stub vs NetworkManager 钩子）
3. 打包优先级：`.deb` 先还是 AppImage 先（Flatpak 沙箱拿不到 CAP_NET_ADMIN，需单独方案）
