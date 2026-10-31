import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/platform/android_foreground.dart';
import 'core/platform/windows_tray.dart';
import 'ui/screens/share_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows) {
    await WindowsTrayManager.instance.init();
  } else if (Platform.isAndroid) {
    await AndroidForegroundServiceManager.init();
  }

  runApp(
    const ProviderScope(
      child: HotspotShareApp(),
    ),
  );
}

class HotspotShareApp extends StatelessWidget {
  const HotspotShareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hotspot Share',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: const SharePage(),
    );
  }
}
