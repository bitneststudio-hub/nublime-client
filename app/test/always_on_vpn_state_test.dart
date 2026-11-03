import 'package:flutter_test/flutter_test.dart';
import 'package:nublime/features/settings/model/always_on_vpn_state.dart';

void main() {
  group('AlwaysOnVpnState', () {
    test('enabled only when this app is always-on AND lockdown is on', () {
      final state = AlwaysOnVpnState.fromChannelValue({
        'supported': true,
        'alwaysOnApp': 'com.nublime.vpn',
        'isThisApp': true,
        'lockdown': true,
      });
      expect(state.status, AlwaysOnVpnStatus.enabled);
      expect(state.isProtected, isTrue);
    });

    test('partial when this app is always-on but lockdown is off', () {
      final state = AlwaysOnVpnState.fromChannelValue({
        'supported': true,
        'alwaysOnApp': 'com.nublime.vpn',
        'isThisApp': true,
        'lockdown': false,
      });
      expect(state.status, AlwaysOnVpnStatus.partial);
      expect(state.isProtected, isFalse);
    });

    test('disabled when another app (or nothing) is the always-on VPN', () {
      final other = AlwaysOnVpnState.fromChannelValue({
        'supported': true,
        'alwaysOnApp': 'com.other.vpn',
        'isThisApp': false,
        'lockdown': true,
      });
      expect(other.status, AlwaysOnVpnStatus.disabled);

      final none = AlwaysOnVpnState.fromChannelValue({
        'supported': true,
        'alwaysOnApp': null,
        'isThisApp': false,
        'lockdown': false,
      });
      expect(none.status, AlwaysOnVpnStatus.disabled);
    });

    test('unknown when the system settings cannot be read', () {
      final state = AlwaysOnVpnState.fromChannelValue({
        'supported': false,
        'error': 'SecurityException',
      });
      expect(state.status, AlwaysOnVpnStatus.unknown);
      expect(state.error, 'SecurityException');
      expect(state.isProtected, isFalse);
    });

    test('unknown for a malformed payload — never silently "enabled"', () {
      expect(AlwaysOnVpnState.fromChannelValue(null).status,
          AlwaysOnVpnStatus.unknown);
      expect(AlwaysOnVpnState.fromChannelValue('ok').status,
          AlwaysOnVpnStatus.unknown);
      expect(AlwaysOnVpnState.fromChannelValue(<String, dynamic>{}).status,
          AlwaysOnVpnStatus.unknown);
    });

    test('a "true" string for lockdown still counts (some ROMs store strings)', () {
      final state = AlwaysOnVpnState.fromChannelValue({
        'supported': true,
        'alwaysOnApp': 'com.nublime.vpn',
        'isThisApp': true,
        'lockdown': 'true',
      });
      // The Kotlin side normalises this to a bool; a raw string must not be
      // mistaken for the bool `true` here.
      expect(state.status, AlwaysOnVpnStatus.partial);
    });
  });
}
