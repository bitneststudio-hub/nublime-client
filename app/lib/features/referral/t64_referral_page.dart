// lib/features/referral/referral_page.dart
// T64: 推荐码页 - v14 规范 Section 14（含二维码 + 分享）

import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/theme/t57_nublime_colors.dart';
import '../../core/auth/t59_auth_token_storage.dart';
import '../../core/model/constants.dart';

/// 推荐信息模型（MVP 统计版 — 天数 + 月度进度）
class ReferralInfo {
  final String code;
  final String link;
  final int totalReferred;
  final int completed;
  final int pending;
  final int expired;
  final int totalRewardDays;
  final int currentMonthRewardDays;
  final int monthlyCapDays;

  const ReferralInfo({
    required this.code,
    required this.link,
    this.totalReferred = 0,
    this.completed = 0,
    this.pending = 0,
    this.expired = 0,
    this.totalRewardDays = 0,
    this.currentMonthRewardDays = 0,
    this.monthlyCapDays = 90,
  });
}

/// 推荐码页面
/// 
/// 功能：
/// - 显示个人推荐码
/// - 二维码生成与展示
/// - 一键分享（复制链接/分享图片）
/// - 推荐统计（总推荐/活跃用户/奖励金额）
/// - 推荐记录列表
class ReferralPage extends StatefulWidget {
  const ReferralPage({super.key});

  @override
  State<ReferralPage> createState() => _ReferralPageState();
}

class _ReferralPageState extends State<ReferralPage> {
  bool get isZh => Localizations.localeOf(context).languageCode == 'zh';
  ReferralInfo? _referralInfo;
  List<Map<String, dynamic>> _history = [];
  bool _isLoading = true;
  String? _errorMessage;
  final GlobalKey _qrKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadReferralInfo();
    _loadHistory();
  }

  /// 加载推荐信息
  Future<void> _loadReferralInfo() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _fetchReferralFromAPI();
      
      setState(() {
        _referralInfo = response;
        _isLoading = false;
        _errorMessage = null;
      });
      // 拿到推荐码后，异步加载统计数据
      _loadStats();
    } catch (e) {
      debugPrint('❌ 加载推荐信息失败：$e');
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  /// 从 API 获取推荐码/邀请链接（my-code 接口）
  Future<ReferralInfo> _fetchReferralFromAPI() async {
    final storage = AuthTokenStorage();
    final authToken = await storage.getToken();
    if (authToken == null) {
      throw Exception('未登录，请先激活账号');
    }

    String code = '';
    String link = '';
    try {
      final response = await http.get(
        Uri.parse('${Constants.apiBaseUrl}/app/referral/my-code'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${authToken.token}',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['success'] == true) {
          final refData = data['data'] ?? data;
          code = (refData['referralCode'] as String?) ?? '';
          link = (refData['inviteUrl'] as String?) ?? '';
        }
      }
    } catch (e) {
      debugPrint('[REFERRAL-API] my-code error: $e');
    }

    // 纯净版：不再有任何基于 activationCode 的 fallback
    return ReferralInfo(code: code, link: link);
  }

  /// 加载统计数据（stats 接口）
  Future<void> _loadStats() async {
    try {
      final token = await AuthTokenStorage().getToken();
      if (token == null || _referralInfo == null) return;
      final res = await http.get(
        Uri.parse('${Constants.apiBaseUrl}/app/referral/stats'),
        headers: {'Authorization': 'Bearer ${token.token}'},
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['success'] == true) {
          final s = data['data'] ?? data;
          setState(() {
            _referralInfo = ReferralInfo(
              code: _referralInfo!.code,
              link: _referralInfo!.link,
              totalReferred: (s['totalReferred'] as int?) ?? 0,
              completed: (s['completed'] as int?) ?? 0,
              pending: (s['pending'] as int?) ?? 0,
              expired: (s['expired'] as int?) ?? 0,
              totalRewardDays: (s['totalRewardDays'] as int?) ?? 0,
              currentMonthRewardDays: (s['currentMonthRewardDays'] as int?) ?? 0,
              monthlyCapDays: (s['monthlyCapDays'] as int?) ?? 90,
            );
          });
        }
      }
    } catch (e) {
      debugPrint('[REFERRAL-STATS] error: $e');
    }
  }

  Future<void> _loadHistory() async {
    try {
      final token = await AuthTokenStorage().getToken();
      if (token == null) return;
      final res = await http.get(
        Uri.parse('https://www.nublime.com/api/app/referral/history'),
        headers: {'Authorization': 'Bearer ${token.token}'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['data'] != null) {
          setState(() {
            _history = List<Map<String, dynamic>>.from(data['data']);
          });
        }
      }
    } catch (_) {}
  }

  /// 复制推荐码
  Future<void> _copyCode() async {
    if (_referralInfo == null || _referralInfo!.code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _referralInfo!.code));
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Text(isZh ? '推荐码已复制' : 'Code copied'),
      ]),
      backgroundColor: NuBLimeColors.connected,
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ));
  }

  /// 复制链接
  Future<void> _copyLink() async {
    if (_referralInfo == null || _referralInfo!.link.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _referralInfo!.link));
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Text(isZh ? '链接已复制到剪贴板' : 'Link copied'),
      ]),
      backgroundColor: NuBLimeColors.connected,
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ));
  }

  /// 分享推荐码（使用 PRD §6.1 模板）
  Future<void> _shareQR() async {
    if (_referralInfo == null || _referralInfo!.code.isEmpty) return;
    final code = _referralInfo!.code;
    final link = _referralInfo!.link;
    String msg;
    if (isZh) {
      // 用 locale 判断：简体中文优先国内口令版
      // 实际使用中若 locale='zh' 但用户是海外华人，可在设置切换
      msg = '回国还想刷 YouTube/Google/Gmail？我在用野柠檬 VPN，回国前装好就行。'
          '用我的推荐码 $code 激活，你我各得额外使用天数 🍋'
          '\n\n$link';
    } else {
      msg = 'Going back to China? Keep using YouTube/Google like normal. '
          'I use WildLime VPN — install it before you go. '
          'Use my code $code when activating, we both get bonus days 🍋'
          '\n\n$link';
    }
    try {
      await Share.share(msg);
    } catch (_) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.info_outline, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(isZh ? '分享已取消' : 'Share cancelled'),
        ]),
        backgroundColor: NuBLimeColors.connected,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  /// 一键复制分享文案
  Future<void> _copyShareText() async {
    if (_referralInfo == null || _referralInfo!.code.isEmpty) return;
    final code = _referralInfo!.code;
    final link = _referralInfo!.link;
    String text;
    if (isZh) {
      text = '回国还想刷 YouTube/Google/Gmail？我在用野柠檬 VPN，回国前装好就行。'
          '用我的推荐码 $code 激活，你我各得额外使用天数 🍋'
          '\n\n$link';
    } else {
      text = 'Going back to China? Keep using YouTube/Google like normal. '
          'I use WildLime VPN — install it before you go. '
          'Use my code $code when activating, we both get bonus days 🍋'
          '\n\n$link';
    }
    await Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Text(isZh ? '分享文案已复制' : 'Share text copied'),
      ]),
      backgroundColor: NuBLimeColors.connected,
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NuBLimeColors.bg0,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: NuBLimeColors.text0),
        title: Text(
          isZh ? '推荐好友' : 'Refer a Friend',
          style: TextStyle(color: NuBLimeColors.text0),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: NuBLimeColors.text0),
            onPressed: _loadReferralInfo,
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(NuBLimeColors.lemon),
              ),
            )
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_errorMessage != null) {
      return _buildErrorState();
    }

    if (_referralInfo == null) {
      return _buildEmptyState();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 奖励说明卡片
          _buildRewardInfo(),

          const SizedBox(height: 20),

          // 推荐码卡片
          _buildReferralCard(),

          const SizedBox(height: 24),

          // 统计卡片
          _buildStatsCard(),

          const SizedBox(height: 24),

          // 二维码卡片
          _buildQRCard(),

          const SizedBox(height: 24),

          // 分享按钮
          _buildShareButtons(),

          const SizedBox(height: 24),

          // 推荐记录
          _buildReferralHistory(),

          // 底部留白（防导航栏遮挡）
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  /// 空状态
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.card_giftcard,
            size: 64,
            color: NuBLimeColors.text3,
          ),
          const SizedBox(height: 16),
          Text(
            isZh ? '暂无推荐码' : 'No referral code',
            style: TextStyle(
              color: NuBLimeColors.text1,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isZh ? '激活账号后即可获得专属推荐码' : 'Activate to get your referral code',
            style: TextStyle(
              color: NuBLimeColors.text2,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  /// 错误状态（可重试）
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: NuBLimeColors.warning,
            ),
            const SizedBox(height: 16),
Text(
            isZh ? '加载失败' : 'Loading failed',
              style: TextStyle(
                color: NuBLimeColors.text1,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? (isZh ? '未知错误' : 'Unknown error'),
              style: TextStyle(
                color: NuBLimeColors.text2,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadReferralInfo,
              icon: const Icon(Icons.refresh, size: 20),
              label: const Text('重试'),
              style: ElevatedButton.styleFrom(
                backgroundColor: NuBLimeColors.lemon,
                foregroundColor: NuBLimeColors.bg0,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 奖励说明卡片
  Widget _buildRewardInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [NuBLimeColors.lemon.withValues(alpha: 0.08), NuBLimeColors.bg2],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NuBLimeColors.lemon.withValues(alpha: 0.2)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.info_outline, color: NuBLimeColors.lemon, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(isZh ? '推荐奖励' : 'Referral Rewards',
                style: TextStyle(color: NuBLimeColors.lemon, fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              isZh
                  ? '你的好友通过你的推荐码激活，你和好友各获得额外使用天数。好友立即得 7 天，你将在 3 天后获得 15 天。每月最多可得 90 天。'
                  : 'When a friend activates using your code, you both get bonus days. '
                    'They get 7 days instantly, you get 15 days after 3 days. Up to 90 days/month.',
              style: TextStyle(color: NuBLimeColors.text2, fontSize: 13, height: 1.5),
            ),
          ]),
        ),
      ]),
    );
  }

  /// 推荐码卡片
  Widget _buildReferralCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [NuBLimeColors.bg2, NuBLimeColors.bg3],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NuBLimeColors.lemon.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: NuBLimeColors.lemon.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.card_giftcard,
                  color: NuBLimeColors.lemon,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isZh ? '我的推荐码' : 'My Referral Code',
                      style: TextStyle(
                        color: NuBLimeColors.text2,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _referralInfo!.code,
                      style: TextStyle(
                        color: NuBLimeColors.text0,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.copy, color: NuBLimeColors.lemon),
                onPressed: () {
                  if (_referralInfo == null) return;
                  Clipboard.setData(ClipboardData(text: _referralInfo!.code));
                  ScaffoldMessenger.of(context).clearSnackBars();
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Row(children: [
                      const Icon(Icons.check_circle, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text(isZh ? '推荐码已复制' : 'Code copied'),
                    ]),
                    backgroundColor: NuBLimeColors.connected,
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ));
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: NuBLimeColors.border0),
          const SizedBox(height: 16),
          Text(
            isZh ? '邀请链接' : 'Invite Link',
            style: TextStyle(
              color: NuBLimeColors.text1,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: NuBLimeColors.bg1,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _referralInfo!.link.isNotEmpty ? _referralInfo!.link : (isZh ? '加载中...' : 'Loading...'),
                  style: TextStyle(
                    color: NuBLimeColors.text2,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: NuBLimeColors.bg1,
                borderRadius: BorderRadius.circular(8),
              ),
              child: IconButton(
                icon: Icon(Icons.copy, color: NuBLimeColors.lemon, size: 20),
                onPressed: _copyLink,
              ),
            ),
          ]),
        ],
      ),
    );
  }

  /// 统计卡片（已邀/已完成/已得天数 + 月度进度）
  Widget _buildStatsCard() {
    final info = _referralInfo!;
    final progress = info.monthlyCapDays > 0
        ? (info.currentMonthRewardDays / info.monthlyCapDays).clamp(0.0, 1.0)
        : 0.0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: NuBLimeColors.bg2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NuBLimeColors.border0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isZh ? '推荐统计' : 'Referral Stats',
            style: TextStyle(
              color: NuBLimeColors.text1,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildStatItem(Icons.people, '${info.totalReferred}', isZh ? '已邀请' : 'Invited', NuBLimeColors.lemon)),
              Container(width: 1, height: 40, color: NuBLimeColors.border0),
              Expanded(child: _buildStatItem(Icons.check_circle, '${info.completed}', isZh ? '已完成' : 'Completed', NuBLimeColors.connected)),
              Container(width: 1, height: 40, color: NuBLimeColors.border0),
              Expanded(child: _buildStatItem(Icons.calendar_today, '${info.totalRewardDays}', isZh ? '获得天数' : 'Days earned', NuBLimeColors.success)),
            ],
          ),
          const SizedBox(height: 16),
          // 月度进度条
          Row(children: [
            Text(isZh ? '本月进度' : 'Monthly progress', style: TextStyle(color: NuBLimeColors.text2, fontSize: 12)),
            const Spacer(),
            Text('${info.currentMonthRewardDays}/${info.monthlyCapDays} ${isZh ? "天" : "days"}',
                style: TextStyle(color: NuBLimeColors.text2, fontSize: 12)),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: NuBLimeColors.bg3,
              valueColor: AlwaysStoppedAnimation<Color>(NuBLimeColors.lemon),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }

  /// 统计小项
  Widget _buildStatItem(IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(color: NuBLimeColors.text0, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: NuBLimeColors.text2, fontSize: 12)),
      ],
    );
  }

  /// 二维码卡片
  Widget _buildQRCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: NuBLimeColors.bg2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NuBLimeColors.border0),
      ),
      child: Column(
        children: [
          Text(
            isZh ? '扫描二维码' : 'Scan QR Code',
            style: TextStyle(
              color: NuBLimeColors.text1,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          // 二维码
          Container(
            key: _qrKey,
            width: 200,
            height: 200,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: Center(
              child: _referralInfo != null && _referralInfo!.code.isNotEmpty
                  ? QrImageView(data: _referralInfo!.link, version: QrVersions.auto, size: 180, backgroundColor: Colors.white)
                  : const Icon(Icons.qr_code, size: 80, color: NuBLimeColors.text3),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isZh ? '好友扫描二维码即可通过你的链接注册' : 'Friends scan QR code to register via your link',
            style: TextStyle(
              color: NuBLimeColors.text2,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  /// 分享按钮
  Widget _buildShareButtons() {
    return Column(children: [
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _copyLink,
              icon: Icon(Icons.link, color: NuBLimeColors.lemon),
              label: Text(isZh ? '复制链接' : 'Copy Link',
                  style: TextStyle(color: NuBLimeColors.lemon)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: NuBLimeColors.lemon),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _shareQR,
              icon: Icon(Icons.share, color: NuBLimeColors.bg0),
              label: Text(isZh ? '分享' : 'Share',
                  style: TextStyle(color: NuBLimeColors.bg0)),
              style: ElevatedButton.styleFrom(
                backgroundColor: NuBLimeColors.lemon,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _copyShareText,
          icon: Icon(Icons.copy, color: NuBLimeColors.text2, size: 18),
          label: Text(isZh ? '复制分享文案' : 'Copy Share Text',
              style: TextStyle(color: NuBLimeColors.text2)),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: NuBLimeColors.border0),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    ]);
  }

  /// 推荐记录
  Widget _buildReferralHistory() {
    return Container(
      decoration: BoxDecoration(
        color: NuBLimeColors.bg2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NuBLimeColors.border0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
            isZh ? '推荐记录' : 'Referral History',
              style: TextStyle(
                color: NuBLimeColors.text1,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          // Referral history from API
          if (_history.isEmpty)
            Container(padding: const EdgeInsets.all(20), child: Center(child: Text(
              isZh ? '暂无推荐记录' : 'No referral history yet',
              style: const TextStyle(color: NuBLimeColors.text2, fontSize: 13),
            )))
          else
            ..._history.map((r) => _buildHistoryItem(
              email: r['refereeActivationCode'] != null && (r['refereeActivationCode'] as String).isNotEmpty
                  ? '****-****-****-${r['refereeActivationCode']}'
                  : r['referralCode'] ?? '',
              date: r['createdAt'] != null ? DateTime.parse(r['createdAt']) : DateTime.now(),
              reward: (r['rewardDays'] as num?)?.toDouble() ?? 0,
              status: r['status'] ?? 'pending',
            )),
        ],
      ),
    );
  }

  /// 推荐记录项
  Widget _buildHistoryItem({
    required String email,
    required DateTime date,
    required double reward,
    required String status,
  }) {
    // status: pending(观察中)/completed(已完成)/expired(已过期)
    String statusText;
    Color statusColor;
    switch (status) {
      case 'completed':
        statusText = isZh ? '已完成' : 'Completed';
        statusColor = NuBLimeColors.success;
      case 'expired':
        statusText = isZh ? '已过期' : 'Expired';
        statusColor = NuBLimeColors.text3;
      default: // pending or unknown
        statusText = isZh ? '待激活' : 'Pending';
        statusColor = NuBLimeColors.warning;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: NuBLimeColors.border0, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  email,
                  style: TextStyle(
                    color: NuBLimeColors.text0,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${date.year}/${date.month}/${date.day}',
                  style: TextStyle(
                    color: NuBLimeColors.text3,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                reward > 0 ? '+${reward.toInt()}${isZh ? "天" : "d"}' : '',
                style: TextStyle(
                  color: reward > 0 ? NuBLimeColors.lemon : NuBLimeColors.text2,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
