import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/screens/share_page.dart';

void main() {
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
