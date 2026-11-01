import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Rotating local file logger and diagnostics reporter.
class AppLogger {
  static final AppLogger instance = AppLogger._();
  AppLogger._();

  File? _logFile;
  File? _oldLogFile;
  final List<String> _recentLogs = [];
  static const int _maxMemoryLogs = 500;
  static const int _maxFileSizeBytes = 2 * 1024 * 1024; // 2 MB

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    try {
      final dir = await getApplicationSupportDirectory();
      final logDir = Directory('${dir.path}${Platform.pathSeparator}logs');
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }
      _logFile = File('${logDir.path}${Platform.pathSeparator}hotshare.log');
      _oldLogFile = File('${logDir.path}${Platform.pathSeparator}hotshare.log.old');
      _initialized = true;
      log('INFO', 'Logger initialized at ${_logFile?.path}');
    } catch (e) {
      // Fallback in memory only
      _initialized = true;
    }
  }

  void log(String level, String message) {
    final now = DateTime.now().toIso8601String();
    final entry = '[$now] [$level] $message';

    _recentLogs.add(entry);
    if (_recentLogs.length > _maxMemoryLogs) {
      _recentLogs.removeAt(0);
    }

    _writeToFile(entry);
  }

  void _writeToFile(String entry) async {
    if (_logFile == null) return;
    try {
      if (await _logFile!.exists()) {
        final length = await _logFile!.length();
        if (length > _maxFileSizeBytes) {
          if (_oldLogFile != null && await _oldLogFile!.exists()) {
            await _oldLogFile!.delete();
          }
          await _logFile!.rename(_oldLogFile!.path);
        }
      }
      await _logFile!.writeAsString('$entry\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  List<String> getRecentLogs() => List.unmodifiable(_recentLogs);

  Future<String> exportDiagnosticsText({
    String? deviceName,
    String? localIp,
    String? gatewayIp,
    int? pairedDeviceCount,
    int? transferCount,
  }) async {
    final buf = StringBuffer();
    buf.writeln('=== HotShare Diagnostics Report ===');
    buf.writeln('Timestamp: ${DateTime.now().toUtc().toIso8601String()}');
    buf.writeln('Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    buf.writeln('Dart Version: ${Platform.version}');
    buf.writeln('Device Name: ${deviceName ?? "Unknown"}');
    buf.writeln('Local IP: ${localIp ?? "None"}');
    buf.writeln('Gateway IP: ${gatewayIp ?? "None"}');
    buf.writeln('Paired Devices: ${pairedDeviceCount ?? 0}');
    buf.writeln('Total Transfers: ${transferCount ?? 0}');
    buf.writeln('Log File: ${_logFile?.path ?? "In-Memory"}');
    buf.writeln('\n=== Recent Event Logs (${_recentLogs.length} entries) ===');
    for (final line in _recentLogs) {
      buf.writeln(line);
    }
    return buf.toString();
  }
}
