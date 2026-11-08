import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../constants/network_constants.dart';
import '../diagnostics/app_logger.dart';

/// Represents a peer discovered over the local area network via UDP beacon.
class DiscoveredPeer {
  final String deviceId;
  final String name;
  final String platform;
  final String host;
  final int port;
  final DateTime lastSeen;

  DiscoveredPeer({
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.host,
    required this.port,
  }) : lastSeen = DateTime.now();

  @override
  String toString() => '$name ($platform) @ $host:$port [$deviceId]';
}

/// UDP Broadcast Discovery Service.
///
/// Enables zero-configuration device discovery across local Wi-Fi, MiFi routers,
/// and mobile hotspots without requiring users to type IP addresses.
///
/// Runs symmetrically on both Android and Windows.
class LanDiscoveryService {
  static const int discoveryPort = 52524;
  static const String protocolTag = 'hotshare_beacon_v2';

  RawDatagramSocket? _socket;
  Timer? _beaconTimer;
  bool _running = false;

  String _localDeviceId = '';
  String _localDeviceName = '';
  int _localServerPort = kPort;

  final StreamController<DiscoveredPeer> _peerController =
      StreamController<DiscoveredPeer>.broadcast();

  Stream<DiscoveredPeer> get peerDiscovered => _peerController.stream;

  final Map<String, DiscoveredPeer> _discoveredPeers = {};
  List<DiscoveredPeer> get activePeers => _discoveredPeers.values.toList();

  static final LanDiscoveryService instance = LanDiscoveryService._();
  LanDiscoveryService._();

  Future<void> start({
    required String deviceId,
    required String deviceName,
    int serverPort = kPort,
  }) async {
    if (_running) {
      updateIdentity(deviceId: deviceId, deviceName: deviceName);
      return;
    }

    _localDeviceId = deviceId;
    _localDeviceName = deviceName;
    _localServerPort = serverPort;

    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
        reusePort: !Platform.isWindows,
      );
      _socket?.broadcastEnabled = true;
      _running = true;

      _socket?.listen(
        (event) {
          if (event == RawSocketEvent.read) {
            _handleIncomingDatagram();
          }
        },
        onError: (e) {
          AppLogger.instance.log('DISCOVERY', 'Socket error: $e');
        },
      );

      // Periodically broadcast beacon every 2.5 seconds
      _beaconTimer?.cancel();
      _beaconTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
        broadcastBeacon();
      });

      // Send initial burst
      burst();
      AppLogger.instance.log('DISCOVERY', 'LAN discovery listening on UDP :$discoveryPort');
    } catch (e) {
      AppLogger.instance.log('DISCOVERY', 'Failed to bind UDP discovery: $e');
    }
  }

  void updateIdentity({String? deviceId, String? deviceName}) {
    if (deviceId != null && deviceId.isNotEmpty) _localDeviceId = deviceId;
    if (deviceName != null && deviceName.isNotEmpty) _localDeviceName = deviceName;
  }

  void burst() {
    broadcastBeacon();
    Future.delayed(const Duration(milliseconds: 200), broadcastBeacon);
    Future.delayed(const Duration(milliseconds: 600), broadcastBeacon);
  }

  /// Sends a UDP beacon across all local IPv4 broadcast addresses.
  Future<void> broadcastBeacon() async {
    if (_socket == null || _localDeviceId.isEmpty) return;

    final payload = jsonEncode({
      'proto': protocolTag,
      'deviceId': _localDeviceId,
      'name': _localDeviceName,
      'platform': Platform.operatingSystem,
      'port': _localServerPort,
    });
    final bytes = utf8.encode(payload);

    try {
      // 1. Generic broadcast
      _socket?.send(bytes, InternetAddress('255.255.255.255'), discoveryPort);

      // 2. Interface-specific broadcast and hotspot unicast addresses
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          final parts = addr.address.split('.');
          if (parts.length == 4) {
            // Subnet directed broadcast (e.g. 192.168.43.255)
            final subnetBroadcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
            try {
              _socket?.send(bytes, InternetAddress(subnetBroadcast), discoveryPort);
            } catch (_) {}

            // Unicast sweep to common hotspot client addresses (.1 to .30)
            // Hotspot APs filter out broadcast/multicast packets, but pass unicast directly!
            final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
            final myHost = int.tryParse(parts[3]) ?? 0;
            for (var h = 1; h <= 30; h++) {
              if (h == myHost) continue;
              try {
                _socket?.send(bytes, InternetAddress('$prefix.$h'), discoveryPort);
              } catch (_) {}
            }
          }
        }
      }
    } catch (_) {}
  }

  void _handleIncomingDatagram() {
    final dg = _socket?.receive();
    if (dg == null) return;

    try {
      final msg = utf8.decode(dg.data);
      final json = jsonDecode(msg) as Map<String, dynamic>;

      if (json['proto'] != protocolTag) return;
      final peerDeviceId = json['deviceId'] as String?;
      if (peerDeviceId == null || peerDeviceId == _localDeviceId) return;

      final peerName = (json['name'] as String?)?.trim() ?? 'Peer';
      final peerPlatform = (json['platform'] as String?) ?? 'unknown';
      final peerPort = (json['port'] as int?) ?? kPort;
      final peerHost = dg.address.address;

      final peer = DiscoveredPeer(
        deviceId: peerDeviceId,
        name: peerName,
        platform: peerPlatform,
        host: peerHost,
        port: peerPort,
      );

      _discoveredPeers[peerDeviceId] = peer;
      _peerController.add(peer);
    } catch (_) {}
  }

  /// Manually force a re-scan: purges cached peers and sends an immediate beacon burst.
  void rescan() {
    _discoveredPeers.clear();
    burst();
  }

  void stop() {
    _beaconTimer?.cancel();
    _beaconTimer = null;
    _socket?.close();
    _socket = null;
    _running = false;
  }
}
