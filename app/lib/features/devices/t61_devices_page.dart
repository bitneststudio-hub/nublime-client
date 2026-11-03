// lib/features/devices/t61_devices_page.dart
// T61: Device management

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:nublime/core/theme/t57_nublime_colors.dart';
import 'package:nublime/core/auth/t59_auth_token_storage.dart';
import 'package:nublime/core/model/constants.dart';

class DeviceInfo {
  final String id;
  final String name;
  final String os;
  final String osVersion;
  final DateTime lastActive;
  final DateTime? loginAt;
  final DateTime? logoutAt;
  final bool isOnline;
  final String? location;

  const DeviceInfo({
    required this.id,
    required this.name,
    required this.os,
    required this.osVersion,
    required this.lastActive,
    this.loginAt,
    this.logoutAt,
    this.isOnline = false,
    this.location,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> json) => DeviceInfo(
    id: json['id'] ?? json['deviceId'] ?? '',
    name: json['name'] ?? json['deviceName'] ?? 'Unknown',
    os: json['os'] ?? json['deviceType'] ?? 'other',
    osVersion: json['osVersion'] ?? '',
    lastActive: json['lastActive'] != null ? DateTime.parse(json['lastActive']) : DateTime.now(),
    loginAt: json['loginAt'] != null ? DateTime.parse(json['loginAt']) : null,
    logoutAt: json['logoutAt'] != null ? DateTime.parse(json['logoutAt']) : null,
    isOnline: json['isOnline'] ?? false,
    location: json['location'] as String?,
  );
}

class T61DevicesPage extends StatefulWidget {
  const T61DevicesPage({super.key});
  @override State<T61DevicesPage> createState() => _T61DevicesPageState();
}

class _T61DevicesPageState extends State<T61DevicesPage> {
  List<DeviceInfo> _devices = [];
  Map<String, List<DeviceInfo>> _groups = {};
  bool _loading = true;
  String? _error;
  int _limit = 3;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final token = await AuthTokenStorage().getToken();
      if (token == null) { setState(() { _loading = false; _error = 'NOT_AUTH'; }); return; }
      final res = await http.get(
        Uri.parse('${Constants.apiBaseUrl}/app/devices'),
        headers: {'Authorization': 'Bearer ${token.token}'},
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['success'] == true) {
          // Devices may be in data['devices'] or data['data']
          final raw = data['data'] ?? data['devices'];
          final list = (raw is List ? raw : []) as List;
          final all = list.map((d) => DeviceInfo.fromJson(d)).toList();
          // Group by name+os for display
          final groups = <String, List<DeviceInfo>>{};
          for (final d in all) {
            groups.putIfAbsent('${d.name}|${d.os}', () => []).add(d);
          }
          setState(() {
            _groups = groups;
            _devices = groups.values.map((g) => g.reduce((a,b) => a.lastActive.isAfter(b.lastActive) ? a : b)).toList()
              ..sort((a, b) => b.lastActive.compareTo(a.lastActive));
            _limit = (data['deviceLimit'] ?? (data['data'] is Map ? data['data']['deviceLimit'] : null) ?? 5) as int;
            _loading = false;
          });
        } else {
          setState(() { _loading = false; _error = 'EMPTY'; });
        }
      } else {
        setState(() { _loading = false; _error = 'HTTP_${res.statusCode}'; });
      }
    } catch (_) {
      setState(() { _loading = false; _error = 'NETWORK'; });
    }
  }

  Future<void> _deleteDevice(DeviceInfo d) async {
    setState(() => _loading = true);
    try {
      final token = await AuthTokenStorage().getToken();
      if (token == null) { setState(() => _loading = false); return; }
      final group = _groups['${d.name}|${d.os}'] ?? [d];
      for (final device in group) {
        await http.delete(
          Uri.parse('${Constants.apiBaseUrl}/app/devices/${device.id}'),
          headers: {'Authorization': 'Bearer ${token.token}'},
        );
      }
      await _load();
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override Widget build(BuildContext context) {
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    return Scaffold(
      backgroundColor: NuBLimeColors.bg0,
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0,
        leading: const BackButton(color: NuBLimeColors.text0),
        title: Text(isZh ? '设备管理' : 'Devices', style: const TextStyle(color: NuBLimeColors.text0, fontWeight: FontWeight.bold)),
        actions: [IconButton(icon: const Icon(Icons.refresh, color: NuBLimeColors.text2), onPressed: _load)],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: NuBLimeColors.lemon))
        : _buildBody(isZh),
    );
  }

  Widget _buildBody(bool isZh) {
    if (_error != null) {
      final em = switch (_error) {
        'NOT_AUTH' => isZh ? '未登录' : 'Not logged in',
        'NETWORK' => isZh ? '网络错误' : 'Network error',
        'EMPTY' => isZh ? '无法获取设备列表' : 'Cannot fetch device list',
        _ => isZh ? '服务器错误' : 'Server error',
      };
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(em, style: const TextStyle(color: NuBLimeColors.text2, fontSize: 15)),
        const SizedBox(height: 16),
        ElevatedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh, size: 18),
          label: Text(isZh ? '重试' : 'Retry'),
          style: ElevatedButton.styleFrom(backgroundColor: NuBLimeColors.lemon, foregroundColor: NuBLimeColors.bg0)),
      ]));
    }

    return ListView(padding: const EdgeInsets.all(16), children: [
      // Device limit card
      Container(padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: NuBLimeColors.bg2, borderRadius: BorderRadius.circular(12), border: Border.all(color: NuBLimeColors.border0)),
        child: Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: NuBLimeColors.lemon.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.info_outline, color: NuBLimeColors.lemon, size: 22)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(isZh ? '设备上限：$_limit台' : 'Device limit: $_limit', style: const TextStyle(color: NuBLimeColors.text0, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(isZh ? '已登录 ${_devices.length} 台' : '${_devices.length} logged in', style: const TextStyle(color: NuBLimeColors.text2, fontSize: 13)),
          ])),
        ])),
      const SizedBox(height: 20),
      Text(isZh ? '已登录设备' : 'Logged-in Devices', style: const TextStyle(color: NuBLimeColors.text2, fontSize: 13, fontWeight: FontWeight.w500)),
      const SizedBox(height: 8),
      if (_devices.isEmpty)
        Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: NuBLimeColors.bg2, borderRadius: BorderRadius.circular(12), border: Border.all(color: NuBLimeColors.border0)),
          child: Center(child: Text(isZh ? '暂无设备' : 'No devices', style: const TextStyle(color: NuBLimeColors.text2, fontSize: 14))))
      else
        ..._devices.asMap().entries.map((e) => _deviceCard(e.value, e.key == 0, isZh)),
    ]);
  }

  Widget _deviceCard(DeviceInfo d, bool isFirst, bool isZh) {
    final osIcon = switch (d.os.toLowerCase()) {
      'mac' || 'macos' => Icons.desktop_mac,
      'windows' => Icons.desktop_windows,
      'android' => Icons.phone_android,
      'ios' || 'iphone' => Icons.phone_iphone,
      'ipad' => Icons.tablet_mac,
      'linux' => Icons.computer,
      _ => Icons.devices,
    };
    final osLabel = switch (d.os.toLowerCase()) {
      'mac' || 'macos' => isZh ? 'Mac' : 'Mac',
      'windows' => 'Windows',
      'android' => 'Android',
      'ios' || 'iphone' => 'iPhone',
      'ipad' => 'iPad',
      'linux' => 'Linux',
      _ => isZh ? '其他' : 'Other',
    };
    final shortId = d.id.length > 8 ? d.id.substring(0, 8) : d.id;

    return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: NuBLimeColors.bg2, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isFirst ? NuBLimeColors.lemon.withValues(alpha: 0.4) : NuBLimeColors.border0)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(
            color: d.isOnline ? NuBLimeColors.lemon.withValues(alpha: 0.1) : NuBLimeColors.bg3,
            borderRadius: BorderRadius.circular(10)),
            child: Icon(osIcon, color: d.isOnline ? NuBLimeColors.lemon : NuBLimeColors.text2, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('${d.name.isNotEmpty ? d.name : osLabel}', style: const TextStyle(color: NuBLimeColors.text0, fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(width: 8),
              Text('#$shortId', style: const TextStyle(color: NuBLimeColors.text3, fontSize: 10, fontFamily: 'monospace')),
              const SizedBox(width: 8),
              if (d.isOnline) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: NuBLimeColors.connected.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                child: Text(isZh ? '在线' : 'Online', style: const TextStyle(color: NuBLimeColors.connected, fontSize: 10, fontWeight: FontWeight.w600))),
              if (isFirst) ...[
                const SizedBox(width: 6),
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: NuBLimeColors.lemon.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                  child: Text(isZh ? '当前设备' : 'Current', style: const TextStyle(color: NuBLimeColors.lemon, fontSize: 10, fontWeight: FontWeight.w600))),
              ],
            ]),
            const SizedBox(height: 3),
            Text(osLabel, style: const TextStyle(color: NuBLimeColors.text2, fontSize: 12)),
          ])),
        ]),
        const SizedBox(height: 10),
        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: NuBLimeColors.bg0, borderRadius: BorderRadius.circular(8)),
          child: Column(children: [
            _row(isZh ? '最近活跃' : 'Last active', _ago(d.lastActive, isZh)),
            const SizedBox(height: 4),
            if (d.loginAt != null) _row(isZh ? '登录时间' : 'Login time', _fmt(d.loginAt!)),
            if (d.logoutAt != null) ...[
              const SizedBox(height: 4),
              _row(isZh ? '登出时间' : 'Logout time', _fmt(d.logoutAt!)),
            ],
            if (d.isOnline && d.loginAt != null) ...[
              const SizedBox(height: 4),
              _row(isZh ? '在线时长' : 'Duration', _duration(d.loginAt!, d.lastActive, isZh)),
            ],
          ])),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: isFirst ? null : () => _deleteDevice(d),
            icon: const Icon(Icons.delete_outline, size: 16),
            label: Text(isZh ? '删除设备' : 'Remove Device'),
            style: OutlinedButton.styleFrom(
              foregroundColor: NuBLimeColors.error,
              side: BorderSide(color: (isFirst ? NuBLimeColors.border0 : NuBLimeColors.error).withValues(alpha: 0.5)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ),
      ]));
  }

  Widget _row(String l, String v) => Row(children: [
    Text(l, style: const TextStyle(color: NuBLimeColors.text2, fontSize: 12)),
    const Spacer(),
    Text(v, style: const TextStyle(color: NuBLimeColors.text0, fontSize: 12, fontWeight: FontWeight.w500)),
  ]);

  String _ago(DateTime dt, bool isZh) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return isZh ? '刚刚' : 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}${isZh ? "分钟前" : "m ago"}';
    if (diff.inDays < 1) return '${diff.inHours}${isZh ? "小时前" : "h ago"}';
    if (diff.inDays < 30) return '${diff.inDays}${isZh ? "天前" : "d ago"}';
    return _fmt(dt);
  }

  String _duration(DateTime from, DateTime to, bool isZh) {
    final d = to.difference(from);
    if (d.inDays > 0) return '${d.inDays}${isZh ? "天" : "d"} ${d.inHours % 24}${isZh ? "小时" : "h"}';
    if (d.inHours > 0) return '${d.inHours}${isZh ? "小时" : "h"} ${d.inMinutes % 60}${isZh ? "分钟" : "m"}';
    return '${d.inMinutes}${isZh ? "分钟" : "m"}';
  }

  String _fmt(DateTime dt) => '${dt.year}-${_p(dt.month)}-${_p(dt.day)} ${_p(dt.hour)}:${_p(dt.minute)}';
  String _p(int n) => n.toString().padLeft(2, '0');
}
