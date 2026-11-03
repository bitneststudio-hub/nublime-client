import 'package:nublime/nublimecore/model/core_types.dart';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:nublime/core/haptic/haptic_service.dart';
import 'package:nublime/core/preferences/general_preferences.dart';
import 'package:nublime/core/utils/throttler.dart';
import 'package:nublime/features/connection/notifier/connection_notifier.dart';
import 'package:nublime/features/proxy/data/proxy_data_providers.dart';
import 'package:nublime/features/proxy/model/ip_info_entity.dart' as oldipinfo;
import 'package:nublime/features/proxy/model/proxy_failure.dart';
import 'package:nublime/nublimecore/init_signal.dart';
import 'package:nublime/utils/riverpod_utils.dart';
import 'package:nublime/utils/utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'active_proxy_notifier.g.dart';

@riverpod
class IpInfoNotifier extends _$IpInfoNotifier with AppLogger {
  @override
  Future<oldipinfo.IpInfo> build() async {
    ref.disposeDelay(const Duration(seconds: 20));
    final cancelToken = CancelToken();
    Timer? timer;
    ref.onDispose(() {
      loggy.debug("disposing");
      cancelToken.cancel();
      timer?.cancel();
    });

    ref.listen(serviceRunningProvider, (_, next) => _idle = false);

    final autoCheck = ref.watch(Preferences.autoCheckIp);
    final serviceRunning = await ref.watch(serviceRunningProvider.future);
    // loggy.debug(
    //   "idle? [$_idle], forced? [$_forceCheck], connected? [$serviceRunning]",
    // );
    if (!_forceCheck && !serviceRunning) {
      throw const ServiceNotRunning();
    } else if ((_idle && !_forceCheck) || (!_forceCheck && serviceRunning && !autoCheck)) {
      throw const UnknownIp();
    }

    _forceCheck = false;
    final info = await ref.watch(proxyRepositoryProvider).getCurrentIpInfo(cancelToken).getOrElse((err) {
      loggy.warning("error getting proxy ip info", err, StackTrace.current);
      // throw err; //nublime: remove exception to be logged
      throw const UnknownIp();
    }).run();

    timer = Timer(const Duration(seconds: 10), () {
      loggy.debug("entering idle mode");
      _idle = true;
      ref.invalidateSelf();
    });

    return info;
  }

  bool _idle = false;
  bool _forceCheck = false;

  Future<void> refresh() async {
    if (state.isLoading) return;
    loggy.debug("refreshing");
    state = const AsyncLoading();
    await ref.read(hapticServiceProvider.notifier).lightImpact();
    _forceCheck = true;
    ref.invalidateSelf();
  }
}

@Riverpod(keepAlive: true)
class ActiveProxyNotifier extends _$ActiveProxyNotifier with AppLogger {
  @override
  Stream<OutboundGroupItemInfo> build() async* {
    // ref.disposeDelay(const Duration(seconds: 20));
    ref.watch(coreRestartSignalProvider);
    final serviceRunning = await ref.watch(serviceRunningProvider.future);
    if (!serviceRunning) {
      throw const ServiceNotRunning();
    }
    final proxyprovider = ref.watch(proxyRepositoryProvider);
    yield* proxyprovider
        .watchActiveProxies()
        .map((event) => event.getOrElse((l) => List<OutboundGroupInfo>.empty()))
        .map((event) => event.firstOrNull?.items.first ?? OutboundGroupItemInfo());
  }

  final _urlTestThrottler = Throttler(const Duration(seconds: 1));

  Future<void> urlTest(String? groupTag_) async {
    final groupTag = groupTag_ ?? "";
    _urlTestThrottler(() async {
      if (state case AsyncData()) {
        await ref.read(hapticServiceProvider.notifier).lightImpact();
        await ref.read(proxyRepositoryProvider).urlTest(groupTag).getOrElse((err) {
          loggy.warning("error testing group", err);
          throw err;
        }).run();
      }
    });
  }
}
