import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/diagnostics/app_logger.dart';
import 'core/platform/android_foreground.dart';
import 'core/platform/share_target_service.dart';
import 'core/platform/windows_tray.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  await AppLogger.instance.init();
  ShareTargetService.instance.init();

  if (args.contains('--send')) {
    final idx = args.indexOf('--send');
    final paths = args.sublist(idx + 1).where((p) => !p.startsWith('--')).toList();
    ShareTargetService.instance.deliverCommandLineFiles(paths);
  }

  if (Platform.isWindows) {
    await WindowsTrayManager.instance.init();
  } else if (Platform.isAndroid) {
    await AndroidForegroundServiceManager.init();
  }

  runApp(
    const ProviderScope(
      child: HotShareApp(),
    ),
  );
}
