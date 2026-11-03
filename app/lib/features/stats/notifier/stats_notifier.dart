import 'package:nublime/nublimecore/model/core_types.dart';
import 'package:nublime/features/connection/notifier/connection_notifier.dart';
import 'package:nublime/features/stats/data/stats_data_providers.dart';
import 'package:nublime/utils/custom_loggers.dart';
import 'package:nublime/utils/riverpod_utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'stats_notifier.g.dart';

@riverpod
class StatsNotifier extends _$StatsNotifier with AppLogger {
  @override
  Stream<StatsInfo> build() async* {
    ref.disposeDelay(const Duration(seconds: 10));
    final serviceRunning = await ref.watch(serviceRunningProvider.future);
    if (serviceRunning) {
      yield* ref
          .watch(statsRepositoryProvider)
          .watchStats()
          .map((event) => event.getOrElse((_) => StatsInfo.create()));
    } else {
      yield* Stream.value(StatsInfo.create());
    }
  }
}
