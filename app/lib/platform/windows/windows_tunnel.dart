/// Windows 隧道实现：xray.exe 子进程 + Wintun 网卡。
///
/// 设计要点（见 docs/WINDOWS_BRIDGE_CONTRACT.md）：
///  · 不写 C++ —— 起停进程、发现网卡、设 DNS 全部用 Dart Process + PowerShell
///  · 不使用 Android 的 fd/session 语义；sessionId 仅用于状态事件的代数锚定
///  · 配置改造是纯函数，放在 windows_config_builder.dart，可在任何平台单测
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fpdart/fpdart.dart';
import 'package:nublime/features/connection/model/connection_failure.dart';
import 'package:nublime/nublimecore/model/core_status.dart';
import 'package:nublime/platform/windows/windows_config_builder.dart';

/// 网卡名（必须与 tun.settings.name 一致）
const String kWindowsTunName = kDefaultTunName;

/// 本地 stats/api 端口
const int kWindowsApiPort = kDefaultApiPort;

class WindowsTunnel {
  WindowsTunnel({
    String? coreDir,
    String? dataDir,
    Duration adapterTimeout = const Duration(seconds: 15),
    Duration pollInterval = const Duration(seconds: 1),
  })  : coreDir = coreDir ?? _defaultCoreDir(),
        dataDir = dataDir ?? _defaultDataDir(),
        _adapterTimeout = adapterTimeout,
        _pollInterval = pollInterval;

  /// 存放 xray.exe + wintun.dll 的目录
  final String coreDir;

  /// 配置与日志目录（%ProgramData%\WildLime）
  final String dataDir;

  final Duration _adapterTimeout;
  final Duration _pollInterval;

  Process? _process;
  String _sessionId = '';
  int _seq = 0;
  int _generation = 0;
  Timer? _watchdog;
  final StreamController<CoreEvent> _status = StreamController<CoreEvent>.broadcast();
  String? _pendingConfig;

  static String _defaultCoreDir() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    return '$exeDir${Platform.pathSeparator}core';
  }

  static String _defaultDataDir() {
    final programData = Platform.environment['ProgramData'] ?? r'C:\ProgramData';
    return '$programData${Platform.pathSeparator}WildLime';
  }

  String get _xrayExe => '$coreDir${Platform.pathSeparator}xray.exe';
  String get _configPath => '$dataDir${Platform.pathSeparator}config.win.json';
  String get _logPath => '$dataDir${Platform.pathSeparator}xray.log';

  /// 状态流。与 Android 侧同形：sessionId + 单调 seq。
  Stream<CoreEvent> watchStatus() => _status.stream;

  /// 记录本次要下发的配置（等价于 Android 侧的 changeOptions）。
  TaskEither<String, Unit> changeOptions(Object options) => TaskEither(() async {
        try {
          _pendingConfig = options is String ? options : jsonEncode(options);
          return right(unit);
        } catch (e) {
          return left('changeOptions failed: $e');
        }
      });

  /// 启动隧道：写配置 → 拉起 xray.exe → 等网卡 → 设 DNS。
  TaskEither<ConnectionFailure, Unit> start(
    String profilePath,
    String name,
    bool disableMemoryLimit, {
    String perAppMode = 'off',
    List<String> perAppPackages = const [],
  }) {
    final generation = ++_generation;
    return TaskEither(() async {
      try {
        final raw = _pendingConfig ?? await File(profilePath).readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) {
          return left(ConnectionFailure.unexpected('delivered profile is not a JSON object'));
        }
        final cfg = buildWindowsXrayConfig(decoded, logPath: _logPath.replaceAll(r'\', '/'));

        if (generation != _generation) {
          return left(ConnectionFailure.unexpected('start superseded before launch'));
        }

        await Directory(dataDir).create(recursive: true);
        await File(_configPath).writeAsString(const JsonEncoder.withIndent('  ').convert(cfg));

        if (!File(_xrayExe).existsSync()) {
          return left(ConnectionFailure.unexpected('xray.exe not found at $_xrayExe'));
        }

        _emit(const CoreStarting());
        await _killLeftover();

        _process = await Process.start(
          _xrayExe,
          ['run', '-c', _configPath],
          workingDirectory: coreDir, // wintun.dll 必须与 xray.exe 同目录
          runInShell: false,
        );
        _sessionId = 'win-${DateTime.now().microsecondsSinceEpoch}';
        _seq = 0;
        _pipeLogs(_process!);

        final up = await _waitForAdapter();
        if (!up) {
          await _terminate();
          _emit(const CoreStopped(message: 'adapter $kWindowsTunName did not come up in time'));
          return left(ConnectionFailure.unexpected(
              'adapter $kWindowsTunName did not appear within ${_adapterTimeout.inSeconds}s'));
        }

        await _applyDns(cfg);
        _startWatchdog();
        _emit(const CoreStarted());
        return right(unit);
      } catch (e) {
        await _terminate();
        _emit(CoreStopped(message: '$e'));
        return left(ConnectionFailure.unexpected('start failed: $e'));
      }
    });
  }

  /// 停止：杀进程 → 清残留路由 → 摘 DNS。
  TaskEither<String, Unit> stop([String? targetSessionId]) => TaskEither(() async {
        try {
          if (targetSessionId != null && _sessionId.isNotEmpty && targetSessionId != _sessionId) {
            return left('stop ignored: session mismatch ($targetSessionId != $_sessionId)');
          }
          _generation++;
          _emit(const CoreStopping());
          await _terminate();
          await _cleanupRoutes();
          _emit(const CoreStopped());
          return right(unit);
        } catch (e) {
          return left('stop failed: $e');
        }
      });

  TaskEither<String, Unit> restart(
    String profilePath,
    String name,
    bool disableMemoryLimit, {
    String perAppMode = 'off',
    List<String> perAppPackages = const [],
  }) =>
      TaskEither(() async {
        final stopped = await stop().run();
        final stopErr = stopped.fold((l) => l, (_) => null);
        if (stopErr != null) return left(stopErr);
        final started = await start(profilePath, name, disableMemoryLimit,
                perAppMode: perAppMode, perAppPackages: perAppPackages)
            .run();
        return started.fold((l) => left('restart failed: $l'), (_) => right(unit));
      });

  /// 释放资源（应用退出时调用）
  Future<void> dispose() async {
    _watchdog?.cancel();
    await _terminate();
    await _status.close();
  }

  // ── 内部实现 ──────────────────────────────────────────────

  void _pipeLogs(Process p) {
    try {
      final sink = File(_logPath).openWrite(mode: FileMode.append);
      p.stdout.listen(sink.add);
      p.stderr.listen(sink.add);
      p.exitCode.then((code) {
        sink.close();
        if (_process == p) {
          _process = null;
          _emit(CoreStopped(message: 'xray exited with code $code'));
        }
      });
    } catch (_) {
      // 日志失败不能影响隧道本身
    }
  }

  Future<bool> _waitForAdapter() async {
    final deadline = DateTime.now().add(_adapterTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await _adapterUp()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  Future<bool> _adapterUp() async {
    final r = await _ps("(Get-NetAdapter -Name '$kWindowsTunName' -ErrorAction SilentlyContinue | "
        "Select-Object -ExpandProperty Status) -join ','");
    return r.trim().toLowerCase() == 'up';
  }

  Future<void> _applyDns(Map<String, dynamic> cfg) async {
    final servers = extractDnsServers(cfg);
    final dns = servers.isEmpty ? const ['1.1.1.1', '8.8.8.8'] : servers;
    final list = dns.map((e) => "'$e'").join(',');
    await _ps("Set-DnsClientServerAddress -InterfaceAlias '$kWindowsTunName' "
        "-ServerAddresses @($list) -ErrorAction SilentlyContinue");
    await _ps('Clear-DnsClientCache -ErrorAction SilentlyContinue');
  }

  Future<void> _cleanupRoutes() async {
    await _ps("Get-NetRoute -DestinationPrefix '0.0.0.0/1','128.0.0.0/1' "
        "-ErrorAction SilentlyContinue | Where-Object { \$_.NextHop -ne '0.0.0.0' } | "
        "Remove-NetRoute -Confirm:\$false -ErrorAction SilentlyContinue");
  }

  Future<void> _killLeftover() async {
    await _ps('Get-Process xray -ErrorAction SilentlyContinue | Stop-Process -Force');
  }

  Future<void> _terminate() async {
    _watchdog?.cancel();
    final p = _process;
    _process = null;
    if (p == null) {
      await _killLeftover();
      return;
    }
    p.kill();
    try {
      await p.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      p.kill(ProcessSignal.sigkill);
    }
  }

  void _startWatchdog() {
    _watchdog?.cancel();
    var misses = 0;
    _watchdog = Timer.periodic(_pollInterval, (t) async {
      final p = _process;
      if (p == null) {
        t.cancel();
        return;
      }
      final alive = await _adapterUp();
      if (alive) {
        misses = 0;
        return;
      }
      misses++;
      if (misses >= 3) {
        t.cancel();
        _emit(const CoreStopped(message: 'adapter lost, tunnel down'));
        await _terminate();
      }
    });
  }

  void _emit(CoreStatus status) {
    _seq++;
    _status.add(CoreEvent(status: status, sessionId: _sessionId, seq: _seq));
  }

  Future<String> _ps(String script) async {
    final r = await Process.run(
      'powershell',
      ['-NoProfile', '-NonInteractive', '-Command', script],
      runInShell: false,
    );
    return (r.stdout as String?) ?? '';
  }
}
