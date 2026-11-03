// lib/features/purchase/crypto_purchase_page.dart
//
// In-app crypto checkout (USDT / BTC) via our own backend, which brokers NOWPayments.
//
// Why in-app instead of a link to the website: the marketing site is served from a built image
// whose source is gone, so a crypto option cannot be added there without rebuilding the site.
// The app can call the backend directly, which keeps the payment method reachable and the
// credentials server-side (the API key must never ship in the APK).
//
// Flow: pick plan -> POST /crypto/invoice -> open the hosted invoice page -> NOWPayments calls our
// IPN when the payment settles -> the invoice redirects to /success?ref=... where the code is shown
// once (and emailed if an address was given). The app never handles the code itself.
//
// Three rules learned from the first real payment (2026-10-29, $19.99 settled on chain):
//   * The gateway refuses amounts below ~$11.27. That refusal used to surface only on the hosted
//     page, in English, after the customer had picked a plan. Plans below the minimum are now
//     visibly unavailable here, and the backend minimum is fetched rather than hardcoded.
//   * The hosted invoice is valid for about 15 minutes. A customer who pays late, or a cent short,
//     lands in partially_paid forever and never gets a code — so the window is stated up front.
//   * The code is delivered on the success page (shown exactly once) and by email when the buyer
//     supplied one. Email is optional — the order is keyed by an opaque ref so a buyer without an
//     address can still come back and claim the code.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'package:nublime/core/model/constants.dart';
import 'package:nublime/core/theme/t57_nublime_colors.dart';
import 'package:nublime/features/purchase/crypto_plan_rules.dart';

class CryptoPurchasePage extends StatefulWidget {
  const CryptoPurchasePage({super.key});

  @override
  State<CryptoPurchasePage> createState() => _CryptoPurchasePageState();
}

class _CryptoPurchasePageState extends State<CryptoPurchasePage> {
  final TextEditingController _email = TextEditingController();
  String _planId = cryptoPlans.first.id;
  bool _busy = false;
  String? _error;
  double? _minimumUsd;

  @override
  void initState() {
    super.initState();
    _loadMinimum();
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  /// Ask the backend what the gateway currently accepts. Any failure leaves the minimum unknown
  /// (all plans offered) — the order endpoint re-checks, and a failed lookup must never block sales.
  Future<void> _loadMinimum() async {
    try {
      final res = await http
          .get(Uri.parse('${Constants.apiBaseUrl}/crypto/status'))
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final raw = body['minimumUsd'];
      final min = raw is num ? raw.toDouble() : (raw is String ? double.tryParse(raw) : null);
      if (!mounted) return;
      final preset = firstPayablePlan(cryptoPlans, min);
      setState(() {
        _minimumUsd = min;
        if (preset != null) _planId = preset.id;
      });
    } catch (_) {
      // offline / backend down: page stays usable
    }
  }

  bool _looksLikeEmail(String v) {
    final s = v.trim();
    if (s.isEmpty || s.length > 254) return false;
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(s);
  }

  Future<void> _startPayment(bool isZh) async {
    // 邮箱是可选项：不填也能下单，激活码会在支付成功页显示（只显示一次）。
    // 只有“填了但明显不是邮箱”才拦，避免把码发到一个必然退信的地址。
    final emailInput = _email.text.trim();
    if (emailInput.isNotEmpty && !_looksLikeEmail(emailInput)) {
      setState(() => _error = isZh
          ? '邮箱格式不对（不想留邮箱可以留空）'
          : 'That email looks invalid — leave it empty if you prefer');
      return;
    }
    final plan = cryptoPlans.firstWhere((p) => p.id == _planId, orElse: () => cryptoPlans.first);
    if (!isPlanPayable(plan, _minimumUsd)) {
      setState(() => _error = minimumHint(zh: isZh, minimumUsd: _minimumUsd));
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await http
          .post(
            Uri.parse('${Constants.apiBaseUrl}/crypto/invoice'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'planType': _planId,
              if (emailInput.isNotEmpty) 'email': emailInput,
            }),
          )
          .timeout(const Duration(seconds: 25));

      Map<String, dynamic>? body;
      try {
        body = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {
        body = null;
      }

      if (res.statusCode == 503) {
        setState(() => _error = isZh ? '加密支付暂未开放，请使用信用卡支付' : 'Crypto payments are not available yet');
        return;
      }
      if (res.statusCode == 400 && body?['code'] == 'PLAN_BELOW_MINIMUM') {
        final serverMin = body?['minimumUsd'];
        final min = serverMin is num ? serverMin.toDouble() : _minimumUsd;
        setState(() {
          _minimumUsd = min;
          _error = body?['message']?.toString() ?? minimumHint(zh: isZh, minimumUsd: min);
        });
        return;
      }
      if (res.statusCode != 200) {
        final msg = body?['message']?.toString();
        setState(() => _error = isZh
            ? '下单失败（${res.statusCode}）${msg == null ? '，请稍后再试' : '：$msg'}'
            : 'Order failed (${res.statusCode})${msg == null ? '' : ': $msg'}');
        return;
      }

      final url = (body?['data'] as Map?)?['invoiceUrl']?.toString();
      if (url == null || url.isEmpty) {
        setState(() => _error = isZh ? '下单失败：没有收到支付地址' : 'No payment URL returned');
        return;
      }
      final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        setState(() => _error = isZh ? '无法打开支付页面，请确认已安装浏览器' : 'Could not open the payment page');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = isZh ? '网络错误：无法连接服务器' : 'Network error: cannot reach the server');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    return Scaffold(
      backgroundColor: NuBLimeColors.bg0,
      appBar: AppBar(
        backgroundColor: NuBLimeColors.bg0,
        elevation: 0,
        iconTheme: IconThemeData(color: NuBLimeColors.text0),
        title: Text(
          isZh ? '加密货币支付' : 'Crypto payment',
          style: TextStyle(color: NuBLimeColors.text0, fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Text(
            isZh
                ? '支持 USDT（TRC20）、TRX、BTC 等。支付完成后激活码显示在成功页（只显示一次）；填了邮箱会同时发一份。'
                : 'USDT (TRC20), TRX, BTC and more. When the payment settles the code is shown once on the success page; add an email to also receive it by mail.',
            style: TextStyle(color: NuBLimeColors.text2, fontSize: 13, height: 1.6),
          ),
          const SizedBox(height: 20),
          ...cryptoPlans.map((p) => _planTile(p, isZh)),
          Text(
            minimumHint(zh: isZh, minimumUsd: _minimumUsd),
            style: TextStyle(color: NuBLimeColors.text3, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 20),
          Text(
            isZh ? '邮箱（可选）' : 'Email (optional)',
            style: TextStyle(color: NuBLimeColors.text3, fontSize: 12),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            style: TextStyle(color: NuBLimeColors.text0),
            decoration: InputDecoration(
              hintText: 'you@example.com',
              hintStyle: TextStyle(color: NuBLimeColors.text3),
              filled: true,
              fillColor: NuBLimeColors.bg2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: NuBLimeColors.border0),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _busy ? null : () => _startPayment(isZh),
              style: ElevatedButton.styleFrom(
                backgroundColor: NuBLimeColors.lemon,
                disabledBackgroundColor: NuBLimeColors.bg3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                      ),
                    )
                  : Text(
                      isZh ? '生成订单并支付' : 'Create order and pay',
                      style: TextStyle(color: NuBLimeColors.bg0, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
          ],
          const SizedBox(height: 18),
          Text(
            isZh
                ? '收银台有效约 15 分钟，请在这个时间内按页面显示的准确金额转账；超时或金额不足需要重新下单。\n'
                    '支付由 NOWPayments 处理，本站不接触你的私钥。链上确认后自动开通；'
                    '若 30 分钟后仍未收到激活码，请联系 support@nublime.com 并附上订单号。'
                : 'The checkout page is valid for about 15 minutes — send the exact amount it shows. '
                    'If it expires or you underpay, place a new order.\n'
                    'Payments are processed by NOWPayments; we never see your private keys. '
                    'Access is provisioned after on-chain confirmation. If no code arrives within '
                    '30 minutes, contact support@nublime.com with your order id.',
            style: TextStyle(color: NuBLimeColors.text3, fontSize: 12, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _planTile(CryptoPlan p, bool isZh) {
    final payable = isPlanPayable(p, _minimumUsd);
    final selected = _planId == p.id && payable;
    return GestureDetector(
      onTap: () {
        if (!payable) {
          setState(() => _error = minimumHint(zh: isZh, minimumUsd: _minimumUsd));
          return;
        }
        setState(() {
          _planId = p.id;
          _error = null;
        });
      },
      child: Opacity(
        opacity: payable ? 1 : 0.45,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? NuBLimeColors.bg2 : NuBLimeColors.bg1,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? NuBLimeColors.lemon : NuBLimeColors.border0,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: selected ? NuBLimeColors.lemon : NuBLimeColors.text3,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isZh ? p.zh : p.en,
                      style: TextStyle(color: NuBLimeColors.text0, fontSize: 15),
                    ),
                    // 明确写出"该套餐不支持加密支付"，而不是只靠灰度和点击后的提示
                    if (!payable)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          cryptoUnavailableLabel(zh: isZh),
                          style: TextStyle(color: NuBLimeColors.text3, fontSize: 11),
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                '\$${p.usd.toStringAsFixed(2)}',
                style: TextStyle(color: NuBLimeColors.text1, fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
