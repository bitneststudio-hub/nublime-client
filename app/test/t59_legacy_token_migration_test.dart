// T59-MIGRATE：4.1.2（40102）→ 4.1.3+ 升级时 token 键迁移回归测试
//
// 背景（2026-10-19 真机 E2E 实证）：
//   已发布 4.1.2 的 libapp.so 只含 'auth_token'（commit aefce40）；
//   c09bdb5 把键改名为 'auth_token_storage_key' 但未加迁移；
//   升级后 getToken() 恒为 null → [B-3] 动态刷新 skip: status=0，连接用旧工件。
// 本测试锁定修复契约：新键优先、legacy 回读、命中即迁移、过期即失效。

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nublime/core/auth/t59_auth_token_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _newKey = 'auth_token_storage_key';
const _legacyKey = 'auth_token';
const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

String _tokenJson({
  String token = 'jwt-test-token',
  DateTime? expiresAt,
  String deviceId = 'device-abc',
}) {
  final now = DateTime.now();
  return jsonEncode({
    'token': token,
    'expiresAt': (expiresAt ?? now.add(const Duration(days: 365))).toIso8601String(),
    'deviceId': deviceId,
    'email': null,
    'createdAt': now.subtract(const Duration(hours: 1)).toIso8601String(),
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> secureStore;

  void installSecureStorageMock() {
    secureStore = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
      final key = args['key'] as String?;
      switch (call.method) {
        case 'read':
          return key == null ? null : secureStore[key];
        case 'write':
          if (key != null) secureStore[key] = args['value'] as String;
          return null;
        case 'delete':
          if (key != null) secureStore.remove(key);
          return null;
        case 'containsKey':
          return key != null && secureStore.containsKey(key);
        case 'readAll':
          return Map<String, String>.from(secureStore);
        case 'deleteAll':
          secureStore.clear();
          return null;
        default:
          return null;
      }
    });
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installSecureStorageMock();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  group('T59-MIGRATE secure storage', () {
    test('R1: 仅 legacy 键有 token → 读出并迁移到新键、删除旧键', () async {
      secureStore[_legacyKey] = _tokenJson(token: 'legacy-jwt');
      final storage = AuthTokenStorage(forceSecureStorage: true);

      final token = await storage.getToken();

      expect(token, isNotNull);
      expect(token!.token, 'legacy-jwt');
      expect(secureStore[_newKey], isNotNull, reason: '迁移后新键必须有副本');
      expect(secureStore.containsKey(_legacyKey), isFalse, reason: '迁移成功后旧键应删除');
      expect(jsonDecode(secureStore[_newKey]!)['token'], 'legacy-jwt');
    });

    test('R2: 新键已有 token → 直接返回，不触碰 legacy', () async {
      secureStore[_newKey] = _tokenJson(token: 'new-jwt');
      secureStore[_legacyKey] = _tokenJson(token: 'stale-legacy-jwt');
      final storage = AuthTokenStorage(forceSecureStorage: true);

      final token = await storage.getToken();

      expect(token!.token, 'new-jwt');
      expect(secureStore.containsKey(_legacyKey), isTrue, reason: '新键命中时不应清理 legacy');
    });

    test('R3: 两键皆空 → null（不伪造 token）', () async {
      final storage = AuthTokenStorage(forceSecureStorage: true);
      expect(await storage.getToken(), isNull);
    });

    test('R4: legacy token 已过期 → null，且两键都被清除', () async {
      secureStore[_legacyKey] = _tokenJson(
        token: 'expired-jwt',
        expiresAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      final storage = AuthTokenStorage(forceSecureStorage: true);

      final token = await storage.getToken();

      expect(token, isNull);
      expect(secureStore.containsKey(_newKey), isFalse);
      expect(secureStore.containsKey(_legacyKey), isFalse);
    });

    test('R5: secure 写迁移失败 → 仍返回 legacy token（不因迁移失败而登出）', () async {
      secureStore[_legacyKey] = _tokenJson(token: 'legacy-jwt');
      // 让 write 抛错，模拟 Keystore 写入失败
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
        final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
        switch (call.method) {
          case 'read':
            return secureStore[args['key'] as String?];
          case 'write':
            throw PlatformException(code: 'write_failed');
          case 'delete':
            return null;
          default:
            return null;
        }
      });
      final storage = AuthTokenStorage(forceSecureStorage: true);

      final token = await storage.getToken();

      expect(token, isNotNull);
      expect(token!.token, 'legacy-jwt');
    });
  });

  group('T59-MIGRATE shared_preferences 兜底', () {
    test('R6: 仅 SP legacy 键有 token → 迁移到 SP 新键', () async {
      SharedPreferences.setMockInitialValues({_legacyKey: _tokenJson(token: 'sp-legacy')});
      final storage = AuthTokenStorage(forceSecureStorage: false);

      final token = await storage.getToken();

      expect(token!.token, 'sp-legacy');
      final sp = await SharedPreferences.getInstance();
      expect(sp.getString(_newKey), isNotNull);
      expect(sp.getString(_legacyKey), isNull);
    });

    test('R7: SP 两键皆空 → null', () async {
      final storage = AuthTokenStorage(forceSecureStorage: false);
      expect(await storage.getToken(), isNull);
    });
  });
}
