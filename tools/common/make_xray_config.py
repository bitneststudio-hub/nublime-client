#!/usr/bin/env python3
"""sing-box (backend delivery) -> Xray-core config, Windows/desktop variant.

Mirrors lib/nublimecore/singbox_xray_converter.dart for the outbound/streamSettings
part, but emits a DESKTOP inbound shape:
  * tun  inbound  -> Windows/macOS Wintun/utun (no VpnService fd)
  * socks inbound -> 127.0.0.1:10808, diagnostics only (--with-socks)

Usage:
  python3 make_xray_config.py singbox.json out.json [--with-socks] [--tun-name WildLime]
"""
import argparse, json, sys

FINGERPRINT = "chrome"

def die(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(2)

def pick_outbound(nodes):
    """Backend ships node list or a single vless; selector picks `default`."""
    vless = [n for n in nodes if n.get("type") == "vless"]
    if not vless:
        die("no vless outbound in backend config")
    sel = next((n for n in nodes if n.get("type") == "selector"), None)
    if sel:
        want = sel.get("default") or (sel.get("outbounds") or [None])[0]
        for n in vless:
            if n.get("tag") == want:
                return n
    return vless[0]

def stream_settings(node):
    tls = node.get("tls") or {}
    reality = (tls.get("reality") or {})
    net = node.get("xray_transport") or (node.get("transport") or {}).get("type") or "tcp"
    if reality.get("enabled"):
        ss = {
            "network": net,
            "security": "reality",
            "realitySettings": {
                "serverName": tls.get("server_name", ""),
                "publicKey": reality.get("public_key", ""),
                "shortId": reality.get("short_id", ""),
                "fingerprint": FINGERPRINT,
                "spiderX": "/",
            },
        }
    elif tls.get("enabled"):
        ss = {"network": net, "security": "tls", "tlsSettings": {"serverName": tls.get("server_name", "")}}
    else:
        ss = {"network": net, "security": "none"}
    if net == "ws":
        ws = (node.get("transport") or {})
        ss["wsSettings"] = {"path": ws.get("path", "/"), "headers": {"Host": tls.get("server_name", "")}}
    return ss

def vless_outbound(node, tag="proxy"):
    return {
        "tag": tag,
        "protocol": "vless",
        "settings": {"vnext": [{
            "address": node["server"],
            "port": int(node["server_port"]),
            "users": [{"id": node["uuid"], "encryption": "none",
                       **({"flow": node["flow"]} if node.get("flow") else {})}],
        }]},
        "streamSettings": stream_settings(node),
    }

def routing_rules(src_route, server_ip):
    rules = [{"type": "field", "ip": [f"{server_ip}/32"], "outboundTag": "direct"}]  # anti-loop
    for r in (src_route or {}).get("rules", []):
        if r.get("geoip"):
            rules.append({"type": "field", "ip": [f"geoip:{r['geoip']}"], "outboundTag": resolve_tag(r.get("outbound"))})
        if r.get("geosite"):
            rules.append({"type": "field", "domain": [f"geosite:{r['geosite']}"], "outboundTag": resolve_tag(r.get("outbound"))})
    return rules

def resolve_tag(t):
    return {"proxy": "proxy", "direct": "direct", "block": "block"}.get(t or "", "proxy")

def build(singbox, tun_name=None, with_socks=False, mtu=1420, gateway="10.9.0.1/16"):
    nodes = singbox.get("outbounds") or []
    node = pick_outbound(nodes)
    inbounds = []
    if tun_name:
        inbounds.append({
            "tag": "tun-in",
            "protocol": "tun",
            "settings": {
                "name": tun_name,
                "mtu": mtu,
                "gateway": [gateway],
                "autoSystemRoutingTable": ["0.0.0.0/1", "128.0.0.0/1"],
            },
            "sniffing": {"enabled": True, "destOverride": ["http", "tls", "quic"], "routeOnly": True},
        })
    if with_socks:
        inbounds.append({
            "tag": "socks-in", "protocol": "socks", "listen": "127.0.0.1", "port": 10808,
            "settings": {"auth": "noauth", "udp": True},
            "sniffing": {"enabled": True, "destOverride": ["http", "tls", "quic"], "routeOnly": True},
        })
    inbounds.append({"tag": "api-in", "protocol": "dokodemo-door", "listen": "127.0.0.1", "port": 10085,
                     "settings": {"address": "127.0.0.1"}})
    cfg = {
        "log": {"loglevel": "warning", "access": "none"},
        "inbounds": inbounds,
        "outbounds": [
            vless_outbound(node),
            {"tag": "direct", "protocol": "freedom", "settings": {"domainStrategy": "UseIP"}},
            {"tag": "block", "protocol": "blackhole", "settings": {}},
        ],
        "routing": {
            "domainStrategy": "AsIs",
            "rules": routing_rules(singbox.get("route"), node["server"]),
        },
        "stats": {},
        "api": {"tag": "api", "services": ["StatsService"]},
        "policy": {"system": {"statsInboundUplink": True, "statsInboundDownlink": True}},
    }
    dns = (singbox.get("dns") or {}).get("servers") or []
    servers = [s["address"] for s in dns if str(s.get("address", "")).startswith(("https://", "tcp://", "1.1.1.1", "8.8.8.8", "223.5.5.5"))]
    if servers:
        cfg["dns"] = {"servers": servers[:2]}
    return cfg

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src"); ap.add_argument("dst")
    ap.add_argument("--with-socks", action="store_true")
    ap.add_argument("--tun-name", default=None)
    ap.add_argument("--mtu", type=int, default=1420)
    a = ap.parse_args()
    singbox = json.load(open(a.src, encoding="utf-8"))
    cfg = build(singbox, tun_name=a.tun_name, with_socks=a.with_socks, mtu=a.mtu)
    json.dump(cfg, open(a.dst, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
    ob = cfg["outbounds"][0]
    print(f"OK -> {a.dst}  server={ob['settings']['vnext'][0]['address']}:{ob['settings']['vnext'][0]['port']} "
          f"reality={cfg['outbounds'][0]['streamSettings']['security']} inbounds={[i['tag'] for i in cfg['inbounds']]}")

if __name__ == "__main__":
    main()
