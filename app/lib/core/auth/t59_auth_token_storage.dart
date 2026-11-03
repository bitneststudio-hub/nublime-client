// lib/core/auth/auth_token_storage.dart
// T59: Auth Token 存储 — macOS 使用文件存储（Keychain 在非沙盒 macOS 上有权限问题）

import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nublime/utils/custom_loggers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthToken {
  final String token;
  final DateTime expiresAt;
  final String deviceId;
  final String? email;
  final DateTime createdAt;
  final String? activationCode;
  final int? bonusDays;           // 推荐获赠天数

  const AuthToken({
    required this.token,
    required this.expiresAt,
    required this.deviceId,
    this.email,
    required this.createdAt,
    this.activationCode,
    this.bonusDays,
  });

  bool get isValid => DateTime.now().isBefore(expiresAt);
  
  factory AuthToken.fromJson(Map<String, dynamic> json) {
    return AuthToken(
      token: json['token'] as String,
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      deviceId: json['deviceId'] as String,
      email: json['email'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      activationCode: json['activationCode'] as String?,
      bonusDays: json['bonusDays'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'token': token, 'expiresAt': expiresAt.toIso8601String(),
    'deviceId': deviceId, 'email': email,
    'createdAt': createdAt.toIso8601String(),
    if (activationCode != null) 'activationCode': activationCode,
    if (bonusDays != null) 'bonusDays': bonusDays,
  };
}

class AuthTokenStorage with InfraLogger {
  static const _keyToken = 'auth_token_storage_key';
  // v4.1.2 (40102) 及更早版本使用的键名。c09bdb5 改名时未带迁移，
  // 导致从 4.1.2 升级的用户 token 静默丢失（[B-3] 刷新 skip: status=0）。
  // 读取时必须回读 legacy 键并迁移，否则升级用户永久失去登录态。
  static const _keyTokenLegacy = 'auth_token';
  static const _keyDeviceId = 'device_id';
  
  final FlutterSecureStorage _secureStorage;
  final bool? _forceSecureStorage;

  AuthTokenStorage({bool? forceSecureStorage})
    : _forceSecureStorage = forceSecureStorage,
      _secureStorage = const FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      );

  bool get _useSecureStorage => _forceSecureStorage ?? (Platform.isAndroid || Platform.isIOS);

  Future<void> saveToken(AuthToken token) async {
    final jsonData = jsonEncode(token.toJson());
    if (_useSecureStorage) {
      try {
        await _secureStorage.write(key: _keyToken, value: jsonData,
          aOptions: const AndroidOptions(encryptedSharedPreferences: true),
          iOptions: const IOSOptions(accountName: 'nublime_auth'));
        return;
      } catch (_) {}
      // Fallback: shared_preferences if secure storage fails
    }
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_keyToken, jsonData);
  }

  Future<AuthToken?> getToken() async {
    try {
      String? jsonData;
      if (_useSecureStorage) {
        try {
          jsonData = await _secureStorage.read(key: _keyToken);
        } catch (_) {}
        if (jsonData == null) {
          // 升级迁移：4.1.2 及更早把 token 存在 legacy 键下。
          // 命中即迁移到新键并删除旧键；迁移失败也不影响本次返回。
          try {
            jsonData = await _secureStorage.read(key: _keyTokenLegacy);
          } catch (_) {}
          if (jsonData != null) {
            try {
              await _secureStorage.write(key: _keyToken, value: jsonData,
                aOptions: const AndroidOptions(encryptedSharedPreferences: true),
                iOptions: const IOSOptions(accountName: 'nublime_auth'));
              await _secureStorage.delete(key: _keyTokenLegacy);
              loggy.info('[T59-MIGRATE] auth token migrated from legacy key '
                  '(auth_token -> auth_token_storage_key)');
            } catch (_) {
              loggy.warning('[T59-MIGRATE] legacy token read OK but migration write failed; '
                  'serving legacy token without copy');
            }
          }
        }
      }
      if (jsonData == null) {
        final sp = await SharedPreferences.getInstance();
        jsonData = sp.getString(_keyToken) ?? sp.getString(_keyTokenLegacy);
        if (jsonData != null && sp.getString(_keyToken) == null) {
          await sp.setString(_keyToken, jsonData);
          await sp.remove(_keyTokenLegacy);
          loggy.info('[T59-MIGRATE] auth token migrated from legacy prefs key');
        }
      }
      if (jsonData == null) return null;
      final token = AuthToken.fromJson(jsonDecode(jsonData));
      if (!token.isValid) { await clearToken(); return null; }
      return token;
    } catch (e) {
      return null;
    }
  }

  Future<void> clearToken() async {
    if (_useSecureStorage) {
      try {
        await _secureStorage.delete(key: _keyToken);
      } catch (_) {}
      try {
        await _secureStorage.delete(key: _keyTokenLegacy);
      } catch (_) {}
    }
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_keyToken);
    await sp.remove(_keyTokenLegacy);
  }

  Future<String> getOrCreateDeviceId() async {
    String? deviceId;
    if (_useSecureStorage) {
      try {
        deviceId = await _secureStorage.read(key: _keyDeviceId);
      } catch (_) {}
    }
    if (deviceId == null) {
      final sp = await SharedPreferences.getInstance();
      deviceId = sp.getString(_keyDeviceId);
    }
    if (deviceId == null) {
      deviceId = _generateUUID();
      if (_useSecureStorage) {
        try {
          await _secureStorage.write(key: _keyDeviceId, value: deviceId,
            aOptions: const AndroidOptions(encryptedSharedPreferences: true),
            iOptions: const IOSOptions(accountName: 'nublime_auth'));
        } catch (_) {
          final sp = await SharedPreferences.getInstance();
          await sp.setString(_keyDeviceId, deviceId);
        }
      } else {
        final sp = await SharedPreferences.getInstance();
        await sp.setString(_keyDeviceId, deviceId);
      }
    }
    return deviceId;
  }

  Future<void> clearAll() async {
    await clearToken();
    if (_useSecureStorage) {
      try {
        await _secureStorage.delete(key: _keyDeviceId);
      } catch (_) {}
    }
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_keyDeviceId);
  }

  Future<bool> hasValidToken() async {
    final token = await getToken();
    return token != null && token.isValid;
  }

  String _generateUUID() {
    final random = DateTime.now().millisecondsSinceEpoch;
    return '${_toHex(random)}-${_toHex(random >> 16)}-${_toHex(random >> 32)}-${_toHex(random >> 48)}';
  }
  String _toHex(int v) => (v & 0xFFFF).toRadixString(16).padLeft(4, '0');
}
