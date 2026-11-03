// lib/features/purchase/crypto_plan_rules.dart
//
// Pure rules for the crypto checkout. Kept separate from the widget so they can be unit-tested:
// the interesting logic is "which plans may the gateway actually take money for", and getting it
// wrong produces a dead end on a third-party page in a foreign language.
//
// Live facts (2026-10-29, probed through /v1/min-amount):
//   usdttrc20 ≈ 11.27 USD, trx ≈ 11.86 USD, btc ≈ 12.57 USD
// Our cheapest plan is 7.99 USD, so it is unpayable by crypto at any currency. The backend refuses
// it with 400 PLAN_BELOW_MINIMUM; the UI must not offer it in the first place.

class CryptoPlan {
  const CryptoPlan(this.id, this.zh, this.en, this.usd);

  final String id;
  final String zh;
  final String en;
  final double usd;
}

const List<CryptoPlan> cryptoPlans = <CryptoPlan>[
  CryptoPlan('1month', '1 个月', '1 month', 7.99),
  CryptoPlan('3months', '3 个月', '3 months', 19.99),
  CryptoPlan('1year', '1 年', '1 year', 48.99),
];

/// A plan can be paid only when the gateway minimum is unknown (we must not block sales on a failed
/// lookup) or when its price clears that minimum.
bool isPlanPayable(CryptoPlan plan, double? minimumUsd) {
  if (minimumUsd == null || minimumUsd <= 0) return true;
  return plan.usd >= minimumUsd;
}

/// First plan that clears the minimum, used to preselect something the customer can actually buy.
CryptoPlan? firstPayablePlan(List<CryptoPlan> plans, double? minimumUsd) {
  for (final p in plans) {
    if (isPlanPayable(p, minimumUsd)) return p;
  }
  return null;
}

String minimumHint({required bool zh, required double? minimumUsd}) {
  if (minimumUsd == null || minimumUsd <= 0) {
    return zh ? '加密支付由第三方处理，链上确认后自动开通。' : 'Crypto payments are handled by a third party.';
  }
  final amount = minimumUsd.toStringAsFixed(2);
  return zh
      ? '加密支付最低约 \$$amount，低于该金额的套餐请使用信用卡支付。'
      : 'Crypto payments start at about \$$amount; use a card for cheaper plans.';
}

/// Shown on a plan the gateway cannot charge in crypto (currently the 1-month plan, which sits
/// below the per-currency minimum). A badge, not an error: the plan is still purchasable by card.
String cryptoUnavailableLabel({required bool zh}) =>
    zh ? '不支持加密支付' : 'Crypto unavailable';
