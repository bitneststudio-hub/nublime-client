import 'package:nublime/nublimecore/model/core_types.dart';
import 'package:fpdart/fpdart.dart';
import 'package:nublime/core/utils/exception_handler.dart';
import 'package:nublime/features/stats/model/stats_failure.dart';
import 'package:nublime/nublimecore/nublime_core_service.dart';
import 'package:nublime/utils/custom_loggers.dart';

abstract interface class StatsRepository {
  Stream<Either<StatsFailure, StatsInfo>> watchStats();
}

class StatsRepositoryImpl with ExceptionHandler, InfraLogger implements StatsRepository {
  StatsRepositoryImpl({required this.singbox});

  final NuBLimeCoreService singbox;

  @override
  Stream<Either<StatsFailure, StatsInfo>> watchStats() {
    return singbox.watchStats().handleExceptions(StatsUnexpectedFailure.new);
  }
}
