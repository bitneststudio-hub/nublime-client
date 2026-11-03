import 'package:nublime/nublimecore/nublime_core_service.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'nublime_core_service_provider.g.dart';

/// The Xray-based core service. Stateless MethodChannel/EventChannel bridge —
/// no directories / debug-mode / notification dependencies like the old
/// legacy gRPC service had, so this provider takes no extra dependencies.
@Riverpod(keepAlive: true)
NuBLimeCoreService nublimeCoreService(Ref ref) {
  return NuBLimeCoreService();
}
