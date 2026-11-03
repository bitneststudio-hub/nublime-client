/// 纯函数：把后端下发的（已转换的）Xray 配置改造成 Windows 桌面形态。
///
/// 之所以单独成文件：**这一段可以在 macOS/Linux 上单元测试**，
/// 不需要 Windows 真机，也不触发任何 IO。
///
/// 与 Android 的差别只有 inbound：
///   Android → VpnService 把 fd 交给核心
///   Windows → xray 自己用 Wintun 建网卡（tun inbound）
library;

const String kDefaultTunName = 'WildLime';
const int kDefaultTunMtu = 1420;
const String kDefaultTunGateway = '10.9.0.1/16';
const int kDefaultApiPort = 10085;

/// 双 /1 路由：不抢默认路由，断线时系统网络瞬间恢复。
const List<String> kSplitDefaultRoutes = ['0.0.0.0/1', '128.0.0.0/1'];

final RegExp _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');

bool isIpv4Literal(String s) => _ipv4.hasMatch(s);

/// 从 outbounds 里挑出节点服务器 IP（用于防环直连规则）。
/// 只认 IPv4 字面量：域名作为服务器名时不能加 /32 规则。
String? extractServerIp(List outbounds) {
  for (final ob in outbounds) {
    if (ob is! Map) continue;
    final settings = ob['settings'];
    if (settings is! Map) continue;

    final vnext = settings['vnext'];
    if (vnext is List) {
      for (final v in vnext) {
        final addr = (v is Map) ? v['address'] : null;
        if (addr is String && isIpv4Literal(addr)) return addr;
      }
    }
    final servers = settings['servers'];
    if (servers is List) {
      for (final s in servers) {
        final addr = (s is Map) ? s['address'] : null;
        if (addr is String && isIpv4Literal(addr)) return addr;
      }
    }
  }
  return null;
}

/// 从配置的 dns 段取可用的 IPv4 DNS（tun 用的接口 DNS）。
List<String> extractDnsServers(Map<String, dynamic> cfg) {
  final servers = cfg['dns']?['servers'];
  if (servers is! List) return const [];
  final out = <String>[];
  for (final s in servers) {
    final addr = s is String ? s : (s is Map ? s['address'] : null);
    if (addr is String && isIpv4Literal(addr) && !out.contains(addr)) out.add(addr);
  }
  return out;
}

Map<String, dynamic> buildWindowsXrayConfig(
  Map<String, dynamic> delivered, {
  required String logPath,
  String tunName = kDefaultTunName,
  int mtu = kDefaultTunMtu,
  String gateway = kDefaultTunGateway,
  int apiPort = kDefaultApiPort,
}) {
  final outbounds = (delivered['outbounds'] as List?) ?? const [];
  final serverIp = extractServerIp(outbounds);

  // 注意：pin 的 Xray-core v26.7.11 的 tun 配置只接受
  // name / mtu / gateway / dns / userLevel / autoSystemRoutingTable / autoOutboundsInterface。
  // 其它字段（desc / autoSystemDnsToGateway / autoSystemWfpBlockLeak）是更高版本才有的，
  // 写了会被静默丢弃 —— 且 `xray -test` 不会报错。不要加。
  final tun = <String, dynamic>{
    'tag': 'tun-in',
    'protocol': 'tun',
    'settings': {
      'name': tunName,
      'mtu': mtu,
      'gateway': [gateway],
      'autoSystemRoutingTable': kSplitDefaultRoutes,
    },
    'sniffing': {
      'enabled': true,
      'destOverride': ['http', 'tls', 'quic'],
      'routeOnly': true,
    },
  };

  final api = <String, dynamic>{
    'tag': 'api-in',
    'protocol': 'dokodemo-door',
    'listen': '127.0.0.1',
    'port': apiPort,
    'settings': {'address': '127.0.0.1'},
  };

  final routing = Map<String, dynamic>.from(
      (delivered['routing'] as Map?) ?? const <String, dynamic>{});
  final rules = <Map<String, dynamic>>[
    ...((routing['rules'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e)),
  ];

  // 防环：节点服务器 IP 必须直连，否则 xray 自己的出站会被 routing 拽回 tun
  if (serverIp != null) {
    final rule = '$serverIp/32';
    final already = rules.any((r) {
      final ip = r['ip'];
      return ip is List && ip.contains(rule);
    });
    if (!already) {
      rules.insert(0, {
        'type': 'field',
        'ip': [rule],
        'outboundTag': 'direct',
      });
    }
  }

  return <String, dynamic>{
    ...delivered,
    'log': {
      'loglevel': 'warning',
      'access': 'none',
      'error': logPath,
    },
    'inbounds': [tun, api],
    'routing': {
      ...routing,
      'domainStrategy': routing['domainStrategy'] ?? 'AsIs',
      'rules': rules,
    },
    'stats': delivered['stats'] ?? <String, dynamic>{},
    'api': {
      'tag': 'api',
      'services': ['StatsService'],
    },
    'policy': {
      'system': {
        'statsInboundUplink': true,
        'statsInboundDownlink': true,
      },
    },
  };
}
