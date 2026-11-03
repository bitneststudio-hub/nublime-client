import 'package:nublime/nublimecore/model/core_types.dart';
// ignore_for_file: parameter_assignments

import 'package:dartx/dartx.dart';
import 'package:nublime/features/log/model/log_entity.dart';
import 'package:nublime/features/log/model/log_level.dart';
import 'package:tint/tint.dart';

abstract class LogParser {
  static LogEntity parseLogProto(LogEntry message) {
    final level = switch (message.level) {
      'DEBUG' => LogLevel.debug,
      'INFO' => LogLevel.info,
      'WARNING' => LogLevel.warn,
      'ERROR' => LogLevel.error,
      'FATAL' => LogLevel.fatal,
      _ => LogLevel.debug,
    };

    return LogEntity(level: level, time: message.timestamp, message: message.message);
  }

  static LogEntity parseSingbox(String log) {
    log = log.strip();
    DateTime? time;
    if (log.length > 25) {
      time = DateTime.tryParse(log.substring(6, 25));
    }
    if (time != null) {
      log = log.substring(26);
    }
    final level = LogLevel.values.firstOrNullWhere((e) {
      if (log.startsWith(e.name.toUpperCase())) {
        log = log.removePrefix(e.name.toUpperCase());
        return true;
      }
      return false;
    });
    return LogEntity(level: level, time: time, message: log.trim());
  }
}
