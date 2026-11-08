import 'dart:async';
import 'dart:io';

import '../constants/network_constants.dart';
import '../diagnostics/app_logger.dart';

/// Active Subnet Sweeper.
///
/// Discovers HotShare peers over local networks (especially third-party mobile hotspots,
/// Wi-Fi client isolation networks, and MiFi routers) where UDP broadcast packets
/// (255.255.255.255) are blocked or filtered by the AP router.
///
/// Performs rapid, non-blocking asynchronous TCP socket checks on [kPort] (8080).
class SubnetScanner {
  static bool _isScanning = false;
  static bool get isScanning => _isScanning;

  /// Rapidly scans the local network subnets for any active HotShare instance on [port].
  ///
  /// Calls [onFound] as soon as a peer is discovered so connection can begin immediately.
  /// Returns the list of discovered IP addresses.
  static Future<List<String>> scan({
    int port = kPort,
    Duration probeTimeout = const Duration(milliseconds: 350),
    void Function(String ip)? onFound,
  }) async {
    if (_isScanning) return [];
    _isScanning = true;

    final discovered = <String>[];

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );

      final localIps = <String>{};
      final candidateIps = <String>[];

      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          final ip = addr.address;
          localIps.add(ip);

          final parts = ip.split('.');
          if (parts.length != 4) continue;
          final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
          final myHost = int.tryParse(parts[3]) ?? 0;

          // Priority 1: Gateway and common hotspot DHCP pool (.1 to .35)
          for (var i = 1; i <= 35; i++) {
            if (i == myHost) continue;
            final target = '$prefix.$i';
            if (!candidateIps.contains(target)) candidateIps.add(target);
          }

          // Priority 2: Standard MiFi (Huawei/ZTE) & Home Router DHCP pool (.100 to .160)
          for (var i = 100; i <= 160; i++) {
            if (i == myHost) continue;
            final target = '$prefix.$i';
            if (!candidateIps.contains(target)) candidateIps.add(target);
          }

          // Priority 3: The rest of the subnet (.36 to .99, .161 to .254)
          for (var i = 36; i <= 99; i++) {
            if (i == myHost) continue;
            final target = '$prefix.$i';
            if (!candidateIps.contains(target)) candidateIps.add(target);
          }
          for (var i = 161; i <= 254; i++) {
            if (i == myHost) continue;
            final target = '$prefix.$i';
            if (!candidateIps.contains(target)) candidateIps.add(target);
          }
        }
      }

      if (candidateIps.isEmpty) {
        // Fallback for standard Android hotspot range if interfaces were empty
        for (var i = 1; i <= 30; i++) {
          candidateIps.add('192.168.43.$i');
        }
      }

      AppLogger.instance.log(
        'SCANNER',
        'Subnet scan initiated across ${candidateIps.length} candidate addresses',
      );

      // Probe in concurrent batches of 30 to stay well within OS limits
      const batchSize = 30;
      for (var i = 0; i < candidateIps.length; i += batchSize) {
        final end = (i + batchSize < candidateIps.length) ? i + batchSize : candidateIps.length;
        final batch = candidateIps.sublist(i, end);

        final results = await Future.wait(
          batch.map((ip) => _probeHost(ip, port, probeTimeout)),
        );

        for (final foundIp in results) {
          if (foundIp != null && !localIps.contains(foundIp)) {
            if (!discovered.contains(foundIp)) {
              discovered.add(foundIp);
              AppLogger.instance.log('SCANNER', 'Found HotShare peer at $foundIp:$port');
              if (onFound != null) {
                onFound(foundIp);
              }
            }
          }
        }

        // If we found a peer in the early high-probability range, we can stop early
        if (discovered.isNotEmpty && i >= 60) {
          break;
        }
      }
    } catch (e) {
      AppLogger.instance.log('SCANNER', 'Subnet scan error: $e');
    } finally {
      _isScanning = false;
    }

    return discovered;
  }

  static Future<String?> _probeHost(String ip, int port, Duration timeout) async {
    try {
      final socket = await Socket.connect(
        ip,
        port,
        timeout: timeout,
      );
      socket.destroy();
      return ip;
    } catch (_) {
      return null;
    }
  }
}
