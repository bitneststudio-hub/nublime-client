// test/crypto_plan_rules_test.dart
//
// The rule that cost a real $19.99 to learn: the gateway's minimum (~$11.27 for USDT-TRC20) makes
// our $7.99 plan unpayable. Offering it produces a dead end on a third-party page in English, after
// the customer has already committed to a plan. These tests pin the gating so the UI cannot regress.

import 'package:flutter_test/flutter_test.dart';
import 'package:nublime/features/purchase/crypto_plan_rules.dart';

void main() {
  group('isPlanPayable', () {
    test('refuses plans below the gateway minimum', () {
      const oneMonth = CryptoPlan('1month', '1 个月', '1 month', 7.99);
      expect(isPlanPayable(oneMonth, 11.27), isFalse);
    });

    test('accepts plans at or above the minimum', () {
      const threeMonths = CryptoPlan('3months', '3 个月', '3 months', 19.99);
      expect(isPlanPayable(threeMonths, 11.27), isTrue);
      expect(isPlanPayable(threeMonths, 19.99), isTrue, reason: 'exactly at the minimum is payable');
    });

    test('fails open when the minimum is unknown or nonsense', () {
      const oneMonth = CryptoPlan('1month', '1 个月', '1 month', 7.99);
      expect(isPlanPayable(oneMonth, null), isTrue);
      expect(isPlanPayable(oneMonth, 0), isTrue);
      expect(isPlanPayable(oneMonth, -5), isTrue);
    });
  });

  group('firstPayablePlan', () {
    test('preselects the cheapest plan that clears the minimum', () {
      final p = firstPayablePlan(cryptoPlans, 11.27);
      expect(p?.id, '3months');
    });

    test('falls back to the cheapest plan when the minimum is unknown', () {
      final p = firstPayablePlan(cryptoPlans, null);
      expect(p?.id, '1month');
    });

    test('returns null when nothing clears an absurd minimum', () {
      expect(firstPayablePlan(cryptoPlans, 999), isNull);
    });
  });

  group('minimumHint', () {
    test('states the real number in both languages', () {
      expect(minimumHint(zh: true, minimumUsd: 11.27), contains('\$11.27'));
      expect(minimumHint(zh: false, minimumUsd: 11.27), contains('\$11.27'));
    });

    test('never invents a number when the minimum is unknown', () {
      expect(minimumHint(zh: true, minimumUsd: null), isNot(contains('\$')));
      expect(minimumHint(zh: false, minimumUsd: null), isNot(contains('\$')));
    });
  });

  test('cryptoUnavailableLabel states the limitation in both languages', () {
    expect(cryptoUnavailableLabel(zh: true), contains('不支持'));
    expect(cryptoUnavailableLabel(zh: false).toLowerCase(), contains('crypto'));
  });
}
