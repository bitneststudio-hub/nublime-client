import 'package:nublime/core/directories/directories_provider.dart';
import 'package:nublime/features/log/data/log_path_resolver.dart';
import 'package:nublime/features/log/data/log_repository.dart';
import 'package:nublime/nublimecore/nublime_core_service_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'log_data_providers.g.dart';

@Riverpod(keepAlive: true)
Future<LogRepository> logRepository(LogRepositoryRef ref) async {
  final repo = LogRepositoryImpl(
    singbox: ref.watch(nublimeCoreServiceProvider),
    logPathResolver: ref.watch(logPathResolverProvider),
  );
  await repo.init().getOrElse((l) => throw l).run();
  return repo;
}

@Riverpod(keepAlive: true)
LogPathResolver logPathResolver(LogPathResolverRef ref) {
  return LogPathResolver(ref.watch(appDirectoriesProvider).requireValue.workingDir);
}
