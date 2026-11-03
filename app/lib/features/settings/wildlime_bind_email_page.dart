// lib/features/settings/wildlime_bind_email_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nublime/core/theme/t57_nublime_colors.dart';
import 'package:nublime/core/auth/t59_auth_token_storage.dart';
import 'package:nublime/core/model/constants.dart';
import 'package:nublime/core/localization/locale_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class WildLimeBindEmailPage extends HookConsumerWidget {
  const WildLimeBindEmailPage({super.key});

  /// Returns null on success, or an error message string on failure.
  static Future<String?> _apiBindEmail(String token, String email) async {
    try {
      final res = await http.put(
        Uri.parse('${Constants.apiBaseUrl}/app/account/email'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'email': email}),
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['success'] == true) return null;
        return (data['message'] as String?) ?? '绑定失败，请稍后重试';
      }
      // Try to extract server error message from response body
      try {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return (data['message'] as String?) ?? '服务器错误 (${res.statusCode})';
      } catch (_) {
        return '服务器错误 (${res.statusCode})';
      }
    } on http.ClientException catch (e) {
      return '网络连接失败: ${e.message}';
    } catch (e) {
      return '请求失败: $e';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isChinese = ref.watch(localePreferencesProvider).languageCode == 'zh';
    final controller = useTextEditingController();
    final loading = useState(false);
    final error = useState<String?>(null);
    final success = useState(false);
    // Track bound email locally for duplicate detection
    final storedEmail = useState<String?>(null);

    // Load already-bound email on init
    useEffect(() {
      Future.microtask(() async {
        final sp = await SharedPreferences.getInstance();
        storedEmail.value = sp.getString('bound_email');
      });
      return null;
    }, []);

    Future<void> submit() async {
      final email = controller.text.trim().toLowerCase();
      if (!email.contains('@')) { error.value = isChinese ? '请输入有效的邮件地址' : 'Enter a valid email'; return; }

      // Client-side duplicate detection
      if (storedEmail.value != null) {
        if (email == storedEmail.value) {
          error.value = isChinese ? '此email已经绑定' : 'This email is already linked';
          return;
        } else {
          error.value = isChinese ? '此账号已经绑定过email，无法再次绑定' : 'Account already linked to another email';
          return;
        }
      }

      loading.value = true; error.value = null;
      try {
        final storage = AuthTokenStorage(); final token = await storage.getToken();
        if (token == null) throw Exception('未登录');
        final errMsg = await _apiBindEmail(token.token, email);
        if (errMsg == null) {
          success.value = true;
          // Store bound email locally for future duplicate detection
          final sp = await SharedPreferences.getInstance();
          await sp.setString('bound_email', email);
          storedEmail.value = email;
        } else {
          error.value = errMsg;
        }
      } catch (e) { error.value = e.toString().replaceAll('Exception: ', ''); }
      finally { loading.value = false; }
    }

    return Scaffold(
      backgroundColor: NuBLimeColors.bg0,
      appBar: AppBar(
        backgroundColor: NuBLimeColors.bg1, elevation: 0,
        title: Text(isChinese ? '关联邮件地址' : 'Link Email', style: TextStyle(color: NuBLimeColors.text0, fontWeight: FontWeight.bold)),
        iconTheme: IconThemeData(color: NuBLimeColors.text0),
      ),
      body: Padding(padding: const EdgeInsets.all(24),
        child: success.value
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.check_circle, color: NuBLimeColors.connected, size: 64),
                const SizedBox(height: 16),
                Text(isChinese ? '绑定成功！' : 'Email linked!', style: TextStyle(color: NuBLimeColors.text0, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(controller.text.trim(), style: TextStyle(color: NuBLimeColors.lemon, fontSize: 15)),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: () async {
                    // Clear stored email and allow re-bind
                    final sp = await SharedPreferences.getInstance();
                    await sp.remove('bound_email');
                    storedEmail.value = null;
                    success.value = false;
                    controller.clear();
                  },
                  child: Text(isChinese ? '修改绑定' : 'Change Email', style: TextStyle(color: NuBLimeColors.lemon)),
                ),
              ]))
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(isChinese ? '输入您的邮箱地址' : 'Enter your email', style: TextStyle(color: NuBLimeColors.text2, fontSize: 14)),
                const SizedBox(height: 12),
                TextField(controller: controller, keyboardType: TextInputType.emailAddress,
                  style: TextStyle(color: NuBLimeColors.text0),
                  decoration: InputDecoration(
                    hintText: 'email@example.com', hintStyle: TextStyle(color: NuBLimeColors.text3),
                    filled: true, fillColor: NuBLimeColors.bg2,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    errorText: error.value,
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: loading.value ? null : submit,
                  style: ElevatedButton.styleFrom(backgroundColor: NuBLimeColors.lemon, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: loading.value ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(isChinese ? '绑定' : 'Bind', style: TextStyle(color: NuBLimeColors.bg0, fontWeight: FontWeight.bold)),
                ),
                if (storedEmail.value != null) ...[
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () async {
                      final sp = await SharedPreferences.getInstance();
                      await sp.remove('bound_email');
                      storedEmail.value = null;
                    },
                    child: Text(isChinese ? '修改绑定邮件' : 'Change linked email', style: TextStyle(color: NuBLimeColors.lemon)),
                  ),
                ],
              ]),
      ),
    );
  }
}
