# 发布树扫描报告（R-P5-06）

日期：2026-11-04 · 工具：gitleaks（`gitleaks detect --no-git --redact`）+ 人工复核

## 1. 凭据扫描

| 项 | 结果 |
|---|---|
| 扫描体积 | 3.78 MB |
| 发现 | 4 条，**全部误报** |
| 真实凭据 | **0** |

4 条命中都在 `app/lib/features/profile/details/json_editor.dart`（第 106/142/177/179 行），
内容是 JSON 编辑器空状态的示例模板值。已核对上游 `v4.1.2` 同文件同行为完全相同的内容，
属上游示例数据，非真实凭据。该文件本身在 R0 删除清单内。

## 2. 内网 / 生产地址扫描（含修正记录）

首次扫描发现 **生产节点 IP 出现在测试夹具中**（`app/test/r31f_node_catalog_test.dart`，2 处），
以及内部文档（`docs/techdesign`、`docs/prompts`、`docs/evidence`、`docs/WIN-*`）中大量包含
节点 IP、IPv6 前缀与部署路径。

处理：
1. 测试夹具中的节点 IP → 替换为 RFC 5737 文档保留地址 `198.51.100.7`；
2. `XrayVpnService.kt` 注释中的节点 IPv6 前缀 → 替换为 `2001:db8::/32` 文档地址；
3. 内部文档（techdesign / prompts / evidence / WIN-PLAN / STACK-BASELINE / REVIEW_PROTOCOL 等）
   **全部移出公开仓库**，只保留 `docs/provenance/`（复扫与扫描报告，按审核要求公开）；
4. 重写为单一提交后强推，远程内容已复核：`178.104.17.157` 命中 0。

> 说明：首次公开的提交（短时间存在）含该 IP，已被强推替换；GitHub 端在我方强推后执行回收，
> 旧提交仍可能通过直接 SHA 访问一段时间。该地址是客户端连接用的节点地址，非管理凭据。

## 3. 未被发布的第三方二进制

`libXray.aar`(91 MB)、`jniLibs/*/libgojni.so`、`geoip.dat`/`geosite.dat`、`tools/jvm-suite/runtime/*.jar`
均不在本仓库。已核实 4.1.42 APK 内**不含** geoip/geosite（`unzip -l` 无命中），`tools/jvm-suite`
不参与构建（`grep` 无引用），故不产生 NOTICE 义务。

## 4. 结论

发布树可以公开。libXray 对应源码归档作为 Release 附件补充（R-P5-01）。
