import 'dart:io';

/// Resolves default IPv4 network gateways on Windows by executing `route print -4`.
///
/// Parses the default routes (`0.0.0.0 0.0.0.0 <Gateway> <Interface> <Metric>`),
/// sorting by lowest Metric to pick the active physical network adapter (Wi-Fi hotspot).
Future<List<String>> findWindowsGateways() async {
  if (!Platform.isWindows) return const [];
  try {
    final result = await Process.run('route', ['print', '-4']);
    final stdout = result.stdout.toString();

    // Match all default gateways with their metric:
    // e.g. "0.0.0.0          0.0.0.0    172.27.124.25    172.27.124.70     55"
    final reg = RegExp(
      r'0\.0\.0\.0\s+0\.0\.0\.0\s+(\d+\.\d+\.\d+\.\d+)\s+\S+\s+(\d+)',
    );
    final routeMatches = <({String gateway, int metric})>[];

    for (final m in reg.allMatches(stdout)) {
      final gw = m.group(1)!;
      final metric = int.tryParse(m.group(2)!) ?? 9999;
      // Exclude loopback or unspecified
      if (gw != '0.0.0.0' && gw != '127.0.0.1') {
        routeMatches.add((gateway: gw, metric: metric));
      }
    }

    // Sort by metric (lowest metric = primary active adapter, such as Wi-Fi)
    routeMatches.sort((a, b) => a.metric.compareTo(b.metric));

    final gateways = routeMatches.map((e) => e.gateway).toSet().toList();

    // Fallback: standard hotspot IP if no default route found
    if (!gateways.contains('192.168.43.1')) {
      gateways.add('192.168.43.1');
    }

    return gateways;
  } catch (_) {
    return const ['192.168.43.1'];
  }
}
