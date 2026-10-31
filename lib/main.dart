import 'package:flutter/material.dart';

import 'ui/screens/share_page.dart';

void main() => runApp(const HotspotShareApp());

class HotspotShareApp extends StatelessWidget {
  const HotspotShareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hotspot Share',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: const SharePage(),
    );
  }
}
