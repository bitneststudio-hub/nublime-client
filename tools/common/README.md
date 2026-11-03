# tools/common —— 全平台共用工具

## make_xray_config.py

后端下发的 sing-box JSON → Xray 配置。**五个平台用同一份**，差异只在 inbound：

```bash
# 桌面/移动端 tun（Windows / Linux / macOS）
python3 make_xray_config.py singbox.json config.json --tun-name WildLime

# 本地诊断用（本地 socks 10808，不改系统路由）
python3 make_xray_config.py singbox.json cfg_socks.json --with-socks

# 校验（必须用与服务器同版本的 Xray）
xray -test -c config.json        # 期望：Configuration OK.
```

| 参数 | 作用 |
|---|---|
| `--tun-name` | 生成 `tun` inbound（网卡名）。不传则不生成 tun |
| `--with-socks` | 额外生成 `127.0.0.1:10808` socks inbound（诊断） |
| `--mtu` | 默认 1420 |

与 `app/lib/nublimecore/singbox_xray_converter.dart` 是同一套字段映射；Dart 侧为准，
两边不一致时以 Dart 为准并同步本脚本。

**生成物含节点凭据，不入库、不外发。**
