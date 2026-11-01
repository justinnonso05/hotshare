import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/platform/android_foreground.dart';
import 'core/platform/windows_tray.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

