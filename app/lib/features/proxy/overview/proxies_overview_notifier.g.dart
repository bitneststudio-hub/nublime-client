// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'proxies_overview_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$proxiesSortNotifierHash() =>
    r'cf279518d5aa1b2d039853ef1bc0fe8c21238fd0';

/// See also [ProxiesSortNotifier].
@ProviderFor(ProxiesSortNotifier)
final proxiesSortNotifierProvider =
    NotifierProvider<ProxiesSortNotifier, ProxiesSort>.internal(
      ProxiesSortNotifier.new,
      name: r'proxiesSortNotifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$proxiesSortNotifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$ProxiesSortNotifier = Notifier<ProxiesSort>;
String _$proxiesOverviewNotifierHash() =>
    r'd0a09e101afd57ea6e0ffab53cafda5da2c64308';

/// See also [ProxiesOverviewNotifier].
@ProviderFor(ProxiesOverviewNotifier)
final proxiesOverviewNotifierProvider =
    AutoDisposeStreamNotifierProvider<
      ProxiesOverviewNotifier,
      OutboundGroupInfo?
    >.internal(
      ProxiesOverviewNotifier.new,
      name: r'proxiesOverviewNotifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$proxiesOverviewNotifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$ProxiesOverviewNotifier =
    AutoDisposeStreamNotifier<OutboundGroupInfo?>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
