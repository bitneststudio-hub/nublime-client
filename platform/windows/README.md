# Windows 平台（原生侧）

| 项 | 值 |
|---|---|
| 隧道核心 | 官方 `xray.exe` **子进程**（不用 fd 注入） |
| 虚拟网卡 | **Wintun**（`wintun.dll` 必须与 `xray.exe` 同目录） |
| 权限 | MVP：整个 app `requireAdministrator`（manifest 已改）；W3 换 Win32 服务 |
| Flutter 平台目录 | `app/windows/`（runner 为 Flutter 默认模板，未接核心） |
| 构建脚本 | `tools/windows/` |
| 安装包 | `installer/windows/wildlime.iss` |
| 技术设计 | `docs/techdesign/WildLime_Windows_TechDesign_v1.md` |

## 关键事实（已核实）

- 适配器 **ifIndex 每次启动都变** → 必须按 `FriendlyName == "WildLime"` 动态发现，禁止硬编码
- 路由用双 `/1`（`0.0.0.0/1` + `128.0.0.0/1`），不抢默认路由，断线秒恢复
- 必须放行节点服务器 IP 直连（`routing.rules` 第一条），否则出站被拽回 tun 形成环路
- 运行时核心不入库：`powershell -File tools\windows\fetch_core.ps1` 拉 v26.7.11

## 状态

W0 配置链路已在 macOS 上验证（配置语法 + 节点连通性），Windows 端的 Wintun/路由验证待进行。
