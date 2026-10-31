import 'dart:io';

/// Resolves default IPv4 network gateways on Windows by executing `route print -4`.
Future<List<String>> findWindowsGateways() async {
  if (!Platform.isWindows) return const [];
  try {
    final result = await Process.run('route', ['print', '-4']);
    final gateways = RegExp(r'0\.0\.0\.0\s+0\.0\.0\.0\s+(\d+\.\d+\.\d+\.\d+)')
        .allMatches(result.stdout.toString())
        .map((m) => m.group(1)!)
        .toList();
    return gateways;
  } catch (_) {
    return const [];
  }
}
