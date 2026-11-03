// Slide 1: single source of truth for the marketing bullets shown in About and in Settings.
//
// Why this exists: the same six bullets were copy-pasted in two pages and had already drifted —
// Chinese said "5台设备同时使用" while English said "Up to 3 simultaneous devices", and both
// claimed "支付宝 / 微信支付" although only Stripe (cards) is wired. Duplicated marketing copy
// is a correctness bug waiting to happen, so it lives in one place now.
//
// Rules for editing:
//   * only claim what the backend actually supports (payments: Stripe cards only as of 2026-10);
//   * device count must match the plans sold — quotas are plan-dependent (3 / 5 per plan), so the
//     wording says "up to 5 per plan" rather than promising a flat number to everyone;
//   * both languages must say the same thing.

class FeatureHighlights {
  const FeatureHighlights._();

  static List<String> of({required bool isChinese}) => isChinese
      ? const [
          '基于最新加密协议',
          '多设备同时使用（套餐最高 5 台）',
          '全球高速节点',
          '严格无日志政策',
          '全中文界面',
          '信用卡支付（Stripe）',
        ]
      : const [
          'Latest encryption protocol',
          'Multi-device (up to 5 per plan)',
          'Global high-speed nodes',
          'Strict no-logs policy',
          'Chinese & English UI',
          'Card payments (Stripe)',
        ];
}
