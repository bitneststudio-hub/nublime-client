// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'nublime_core_service_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$nublimeCoreServiceHash() =>
    r'3860ddf9cdbc36d948868d1db1b020509153840e';

/// The Xray-based core service. Stateless MethodChannel/EventChannel bridge —
/// no directories / debug-mode / notification dependencies like the old
/// legacy gRPC service had, so this provider takes no extra dependencies.
///
/// Copied from [nublimeCoreService].
@ProviderFor(nublimeCoreService)
final nublimeCoreServiceProvider = Provider<NuBLimeCoreService>.internal(
  nublimeCoreService,
  name: r'nublimeCoreServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$nublimeCoreServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef NublimeCoreServiceRef = ProviderRef<NuBLimeCoreService>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
