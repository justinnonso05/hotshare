import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Manages system-level sharing: Android Share Sheet intent listening
/// and Windows Explorer context menu & SendTo integration.
class ShareTargetService {
  static const _channel = MethodChannel('com.hotshare.app/share_target');
  static final ShareTargetService instance = ShareTargetService._();

  ShareTargetService._();

  final StreamController<List<String>> _sharedFilesController =
      StreamController<List<String>>.broadcast();

  Stream<List<String>> get sharedFilesStream => _sharedFilesController.stream;

  bool _initialized = false;

  /// Initializes listeners for incoming system shares.
  void init() {
    if (_initialized) return;
    _initialized = true;

    if (Platform.isAndroid) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onFilesShared') {
          final List<dynamic>? files = call.arguments;
          if (files != null && files.isNotEmpty) {
            final paths = files.map((e) => e.toString()).toList();
            _sharedFilesController.add(paths);
          }
        }
      });

      // Query any files shared while the app was cold-started
      _channel.invokeMethod<List<dynamic>>('getInitialSharedFiles').then((files) {
        if (files != null && files.isNotEmpty) {
          final paths = files.map((e) => e.toString()).toList();
          _sharedFilesController.add(paths);
        }
      });
    }
  }

  /// Manually deliver CLI arguments (e.g. from Windows `--send <path>`).
  void deliverCommandLineFiles(List<String> paths) {
    if (paths.isNotEmpty) {
      _sharedFilesController.add(paths);
    }
  }

  /// Asks Android native layer to purge temporary share copy cache.
  Future<void> clearShareCache() async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('clearShareCache');
      } catch (_) {}
    }
  }

  // ── Windows Explorer Integrations ──────────────────────────────────────────

  /// Path to Windows SendTo directory.
  String? get _windowsSendToPath {
    final appData = Platform.environment['APPDATA'];
    if (appData == null) return null;
    return '$appData\\Microsoft\\Windows\\SendTo\\HotShare.lnk';
  }

  /// Checks if the SendTo shortcut exists.
  bool isWindowsSendToEnabled() {
    if (!Platform.isWindows) return false;
    final path = _windowsSendToPath;
    return path != null && File(path).existsSync();
  }

  /// Toggles the Windows "Send To" shortcut.
  Future<bool> setWindowsSendToEnabled(bool enabled) async {
    if (!Platform.isWindows) return false;
    final linkPath = _windowsSendToPath;
    if (linkPath == null) return false;

    if (!enabled) {
      final file = File(linkPath);
      if (file.existsSync()) file.deleteSync();
      return true;
    }

    try {
      final exe = Platform.resolvedExecutable;
      final script =
          "\$ws = New-Object -ComObject WScript.Shell; "
          "\$s = \$ws.CreateShortcut('$linkPath'); "
          "\$s.TargetPath = '$exe'; "
          "\$s.Arguments = '--send'; "
          "\$s.Save()";
      final res = await Process.run('powershell', ['-NoProfile', '-Command', script]);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Checks if the Windows Right-Click context menu registry entry is registered.
  Future<bool> isWindowsContextMenuEnabled() async {
    if (!Platform.isWindows) return false;
    try {
      final res = await Process.run('reg', [
        'query',
        r'HKCU\Software\Classes\*\shell\HotShare',
      ]);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Registers or unregisters the Windows Explorer right-click context menu.
  Future<bool> setWindowsContextMenuEnabled(bool enabled) async {
    if (!Platform.isWindows) return false;
    const regKey = r'HKCU\Software\Classes\*\shell\HotShare';

    if (!enabled) {
      try {
        final res = await Process.run('reg', ['delete', regKey, '/f']);
        return res.exitCode == 0;
      } catch (_) {
        return false;
      }
    }

    try {
      final exe = Platform.resolvedExecutable;
      // Register menu title and command
      await Process.run('reg', [
        'add',
        regKey,
        '/ve',
        '/d',
        'Send with HotShare',
        '/f',
      ]);
      await Process.run('reg', [
        'add',
        regKey,
        '/v',
        'Icon',
        '/d',
        exe,
        '/f',
      ]);
      final cmdRes = await Process.run('reg', [
        'add',
        '$regKey\\command',
        '/ve',
        '/d',
        '"$exe" --send "%1"',
        '/f',
      ]);
      return cmdRes.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
