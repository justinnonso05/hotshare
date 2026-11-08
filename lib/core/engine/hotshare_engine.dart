import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:drift/drift.dart' as drift;

import '../../data/db/app_database.dart';
import '../constants/network_constants.dart';
import '../diagnostics/app_logger.dart';
import '../platform/android_foreground.dart';
import '../security/identity.dart';
import '../security/pairing.dart';
import '../storage/storage_helper.dart';
import '../storage/storage_resolver.dart';
import '../transfer/incoming_transfer.dart';
import '../utils/formatters.dart';
import 'engine_api.dart';

/// Pure Dart implementation of the HotShare engine.
/// Exposes a stream of [EngineEvent]s and receives [EngineCommand]s.
class HotShareEngine {
  final StreamController<EngineEvent> _eventController =
      StreamController<EngineEvent>.broadcast();

  Stream<EngineEvent> get events => _eventController.stream;

  bool get isConnected => _socket != null;
  DeviceIdentity? get identity => _identity;
  String? _localDeviceName;
  void setLocalDeviceName(String name) => _localDeviceName = name;
  bool _pauseReceiving = false;
  void setPauseReceiving(bool val) => _pauseReceiving = val;
  bool _autoAccept = true;
  void setAutoAccept(bool val) => _autoAccept = val;
  final Map<String, Map<String, dynamic>> _pendingIncomingOffers = {};

  final AppDatabase _db;
  final bool _ownsDb;
  DeviceIdentity? _identity;

  HttpServer? _server;
  WebSocket? _socket;

  // Receiving state
  IncomingTransfer? _incoming;
  DateTime? _recvStartTime;
  DateTime? _lastRecvThrottleTime;

  // Benchmark receiving state
  String? _benchmarkIncomingId;
  int _benchmarkExpectedBytes = 0;
  int _benchmarkReceivedBytes = 0;
  DateTime? _benchmarkStartTime;

  // Sending state
  bool _sending = false;
  String? _currentSendingId;
  Completer<int?>? _acceptWaiter;
  Completer<void>? _creditWaiter;
  Completer<bool>? _resultWaiter;
  int _acked = 0;

  // Heartbeat & Persistence
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  DateTime? _lastActivityTime;
  String? _targetHost;
  int _targetPort = kPort;
  bool _autoReconnect = true;
  bool _isConnecting = false;

  // Security, Identity & Pairing
  bool _isAuthenticated = false;
  List<int>? _nonceC;
  List<int>? _nonceS;
  String? _pairingCode;
  DateTime? _pairingExpiry;
  int _pairingAttempts = 0;

  // Pending peer details during pairing
  String? _pendingPeerId;
  String? _pendingPeerName;
  String? _pendingPeerPlatform;
  List<int>? _pendingPeerPubKey;

  HotShareEngine({AppDatabase? db})
      : _db = db ?? AppDatabase(),
        _ownsDb = db == null {
    _initIdentity();
    _runRetentionJob();
  }

  Future<void> _runRetentionJob() async {
    try {
      final cutoff = DateTime.now().subtract(const Duration(days: 90));
      await _db.purgeOldTransfers(cutoff);
    } catch (_) {}
  }

  Future<void> _initIdentity() async {
    try {
      _identity = await DeviceIdentity.loadOrCreate();
      _log('Device identity initialized: ${_identity!.deviceId.substring(0, 8)}...');
    } catch (e) {
      _log('Failed to initialize device identity: $e');
    }
  }

  void send(EngineCommand cmd) {
    if (cmd is StartServerCommand) {
      _startServer(cmd.port);
    } else if (cmd is ConnectCommand) {
      _targetHost = cmd.host;
      _targetPort = cmd.port;
      _connect(cmd.host, cmd.port);
    } else if (cmd is DisconnectCommand) {
      _disconnect();
    } else if (cmd is SendFilesCommand) {
      _sendFiles(cmd.paths);
    } else if (cmd is SendTextCommand) {
      _sendText(cmd.text);
    } else if (cmd is RunBenchmarkCommand) {
      _runBenchmark(cmd.sizeMb);
    } else if (cmd is CancelTransferCommand) {
      _cancelTransfer(cmd.transferId);
    } else if (cmd is SetAutoReconnectCommand) {
      _autoReconnect = cmd.enabled;
      if (!_autoReconnect) {
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
      }
    } else if (cmd is OpenPairingWindowCommand) {
      _openPairingWindow();
    } else if (cmd is SubmitPairingCodeCommand) {
      _submitPairingCode(cmd.code);
    } else if (cmd is ConfirmPairingCommand) {
      _confirmPairing(cmd.isConfirmed);
    } else if (cmd is RevokeDeviceCommand) {
      _revokeDevice(cmd.deviceId);
    } else if (cmd is SetPauseReceivingCommand) {
      setPauseReceiving(cmd.paused);
    } else if (cmd is SetAutoAcceptCommand) {
      setAutoAccept(cmd.enabled);
    } else if (cmd is RespondToTransferOfferCommand) {
      _respondToOffer(cmd.transferId, cmd.accept);
    }
  }

  void _log(String msg) {
    AppLogger.instance.log('ENGINE', msg);
    _eventController.add(LogEvent(msg));
  }

  // ---------------------------------------------------------------------------
  // Networking Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> _startServer(int port) async {
    try {
      _server?.close(force: true);
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _log('Server listening on port $port');

      await AndroidForegroundServiceManager.start();

      final interfaces =
          await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final ni in interfaces) {
        for (final a in ni.addresses) {
          _log('Local address: ${a.address} (${ni.name})');
        }
      }

      _server!.listen((request) async {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          if (_socket != null && _socket!.readyState == WebSocket.open) {
            _log('Rejecting duplicate incoming connection: already connected');
            request.response.statusCode = HttpStatus.conflict;
            await request.response.close();
            return;
          }
          final ws = await WebSocketTransformer.upgrade(
            request,
            compression: CompressionOptions.compressionOff,
          );
          if (_socket != null && _socket!.readyState == WebSocket.open) {
            _log('Closing concurrent incoming socket: already connected');
            await ws.close();
            return;
          }
          _attach(ws, 'Connecting...', isServer: true);
        } else {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        }
      });
    } catch (e) {
      _log('Server error: $e');
    }
  }

  Future<void> _connect(String host, int port, {bool isAutoRetry = false}) async {
    // If already connected, do not re-connect and destroy the working socket!
    if (_socket != null && _socket!.readyState == WebSocket.open) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      return;
    }

    // Prevent concurrent connection attempts from racing
    if (_isConnecting) return;

    final cleanHost = host.trim();
    if (cleanHost.isEmpty) {
      if (!isAutoRetry) _log('Host address cannot be empty');
      return;
    }

    _isConnecting = true;
    if (!isAutoRetry) {
      _log('Connecting to ws://$cleanHost:$port ...');
    }
    try {
      final ws = await WebSocket.connect(
        'ws://$cleanHost:$port',
        compression: CompressionOptions.compressionOff,
      ).timeout(const Duration(seconds: 4));

      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _attach(ws, 'phone', isServer: false);
    } catch (e) {
      if (!isAutoRetry) {
        _log('Connection failed: $e');
      }
      _handleConnectionDrop();
    } finally {
      _isConnecting = false;
    }
  }

  void _attach(WebSocket ws, String peer, {required bool isServer}) {
    if (_socket == ws) return;
    if (_socket != null && _socket!.readyState == WebSocket.open) {
      _log('Discarding duplicate socket: active connection already healthy');
      ws.close();
      return;
    }
    _socket?.close();
    _socket = ws;
    _isAuthenticated = false;
    _lastActivityTime = DateTime.now();

    _startHeartbeat(ws);

    if (!isServer) {
      _eventController.add(PeerStateEvent(
        isConnected: true,
        peerName: peer,
        isPaired: false,
        isAuthenticated: false,
      ));
      _log('Socket connected ($peer)');
      _sendHello(ws);
    } else {
      _log('Socket connected (awaiting hello from peer)');
    }

    ws.listen(
      (data) => _onData(data, peer),
      onDone: () {
        _log('Disconnected');
        if (_socket == ws) {
          _socket = null;
          _isAuthenticated = false;
          _stopHeartbeat();
          _eventController.add(const PeerStateEvent(isConnected: false));
          _abortIncoming('connection closed');
          _handleConnectionDrop();
        }
      },
      onError: (e) {
        _log('Socket error: $e');
        _stopHeartbeat();
        _handleConnectionDrop();
      },
    );
  }

  void _startHeartbeat(WebSocket ws) {
    _heartbeatTimer?.cancel();
    _lastActivityTime = DateTime.now();

    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_socket != ws) {
        _stopHeartbeat();
        return;
      }

      if (_lastActivityTime != null &&
          DateTime.now().difference(_lastActivityTime!).inSeconds >= 15) {
        _log('Heartbeat timeout (no response for 15s)');
        ws.close();
        return;
      }

      try {
        ws.add(jsonEncode({
          't': 'ping',
          'ts': DateTime.now().millisecondsSinceEpoch,
        }));
      } catch (_) {}
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _handleConnectionDrop() {
    if (_autoReconnect && _targetHost != null) {
      if (_reconnectTimer != null && _reconnectTimer!.isActive) return;

      _reconnectTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (_socket != null) {
          _reconnectTimer?.cancel();
          _reconnectTimer = null;
          return;
        }
        _connect(_targetHost!, _targetPort, isAutoRetry: true);
      });
    }
  }

  void _disconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stopHeartbeat();
    _socket?.close();
    _socket = null;
    _server?.close(force: true);
    _server = null;
    _isAuthenticated = false;
    _eventController.add(const PeerStateEvent(isConnected: false));
    AndroidForegroundServiceManager.stop();
  }

  // ---------------------------------------------------------------------------
  // Protocol v2 Handshake & Pairing
  // ---------------------------------------------------------------------------

  Future<void> _sendHello(WebSocket ws) async {
    if (_identity == null) await _initIdentity();
    final rand = Random.secure();
    _nonceC = List<int>.generate(16, (_) => rand.nextInt(256));

    final deviceName = (_localDeviceName != null && _localDeviceName!.isNotEmpty)
        ? _localDeviceName!
        : (Platform.isWindows ? 'Windows PC' : 'Android Phone');
    ws.add(jsonEncode({
      't': 'hello',
      'v': 2,
      'deviceId': _identity!.deviceId,
      'name': deviceName,
      'platform': Platform.operatingSystem,
      'pubKey': _identity!.publicKeyBytes,
      'nonce': _nonceC,
    }));
  }

  Future<void> _onHello(Map<String, dynamic> m) async {
    final ws = _socket;
    if (_identity == null) await _initIdentity();
    if (ws == null || _identity == null) return;

    final peerId = m['deviceId'] as String;
    final peerName = m['name'] as String;
    final peerPlatform = m['platform'] as String;
    final peerPubKey = List<int>.from(m['pubKey'] as List);
    final nonceC = List<int>.from(m['nonce'] as List);
    _nonceC = nonceC;

    final rand = Random.secure();
    final nonceS = List<int>.generate(16, (_) => rand.nextInt(256));
    _nonceS = nonceS;

    _pendingPeerId = peerId;
    _pendingPeerName = peerName;
    _pendingPeerPlatform = peerPlatform;
    _pendingPeerPubKey = peerPubKey;

    final knownDevice = await _db.findDeviceById(peerId);
    final isPaired = knownDevice != null && !knownDevice.revoked;

    final myName = (_localDeviceName != null && _localDeviceName!.isNotEmpty)
        ? _localDeviceName!
        : (Platform.isWindows ? 'Windows PC' : 'Android Phone');

    if (isPaired) {
      if (knownDevice.name != peerName &&
          peerName.isNotEmpty &&
          peerName != 'phone' &&
          peerName != 'Windows PC' &&
          peerName != 'Android Phone') {
        await _db.updateDeviceName(peerId, peerName);
      }
      await _db.updateLastSeen(peerId, _targetHost ?? 'local');
      final transcript = utf8.encode(
          'hotshare/v2|$peerId|${_identity!.deviceId}|${_hex(nonceC)}|${_hex(nonceS)}');
      final sigS = await _identity!.sign(transcript);

      ws.add(jsonEncode({
        't': 'hello_ack',
        'v': 2,
        'deviceId': _identity!.deviceId,
        'name': myName,
        'nonce': nonceS,
        'sig': sigS,
        'known': true,
      }));

      _log('Paired device connected: $peerName ($peerId)');
      _eventController.add(PeerStateEvent(
        isConnected: true,
        peerName: peerName,
        isPaired: true,
        isAuthenticated: false,
      ));
    } else {
      ws.add(jsonEncode({
        't': 'hello_ack',
        'v': 2,
        'deviceId': _identity!.deviceId,
        'name': myName,
        'nonce': nonceS,
        'known': false,
        'revoked': knownDevice != null && knownDevice.revoked,
      }));

      _log('Unpaired device connected: $peerName ($peerId)');
      _eventController.add(PeerStateEvent(
        isConnected: true,
        peerName: peerName,
        isPaired: false,
        isAuthenticated: false,
      ));
    }
  }

  Future<void> _onHelloAck(Map<String, dynamic> m) async {
    final ws = _socket;
    if (_identity == null) await _initIdentity();
    if (ws == null || _identity == null) return;

    final peerId = m['deviceId'] as String;
    final peerName = m['name'] as String;
    final nonceS = List<int>.from(m['nonce'] as List);
    _nonceS = nonceS;
    final isKnown = m['known'] == true;
    final peerRevoked = m['revoked'] == true;

    // Symmetrical unpair sync: if peer revoked or does not know us, reset local trust immediately
    if (peerRevoked || !isKnown) {
      await _db.revokeDevice(peerId);
      _log('Peer has not paired or has forgotten this device. Resetting pairing.');
      _isAuthenticated = false;
      _eventController.add(PeerStateEvent(
        isConnected: true,
        peerName: peerName,
        isPaired: false,
        isAuthenticated: false,
      ));
      return;
    }

    if (isKnown) {
      final knownDevice = await _db.findDeviceById(peerId);
      if (knownDevice == null || knownDevice.revoked) {
        // Peer thinks we are paired, but we don't have peer paired! Notify peer to reset trust!
        ws.add(jsonEncode({'t': 'revoke', 'deviceId': _identity!.deviceId}));
        _log('Peer believed we were paired, but local device forgot peer. Sent revoke notice.');
        _isAuthenticated = false;
        _eventController.add(PeerStateEvent(
          isConnected: true,
          peerName: peerName,
          isPaired: false,
          isAuthenticated: false,
        ));
        return;
      }

      if (knownDevice.name != peerName &&
          peerName.isNotEmpty &&
          peerName != 'phone' &&
          peerName != 'Windows PC' &&
          peerName != 'Android Phone') {
        await _db.updateDeviceName(peerId, peerName);
      }
      await _db.updateLastSeen(peerId, _targetHost ?? 'local');
      final sigS = List<int>.from(m['sig'] as List);
      final transcript = utf8.encode(
          'hotshare/v2|${_identity!.deviceId}|$peerId|${_hex(_nonceC!)}|${_hex(nonceS)}');

      final valid = await DeviceIdentity.verify(
        message: transcript,
        signature: sigS,
        publicKeyBytes: knownDevice.publicKey,
      );

      if (valid) {
        final clientTranscript = utf8.encode(
            'hotshare/v2|${_identity!.deviceId}|$peerId|${_hex(_nonceC!)}|${_hex(nonceS)}|auth');
        final sigC = await _identity!.sign(clientTranscript);

        ws.add(jsonEncode({'t': 'auth', 'sig': sigC}));
        _isAuthenticated = true;
        _log('Authenticated with paired device: $peerName');

        _eventController.add(PeerStateEvent(
          isConnected: true,
          peerName: peerName,
          isPaired: true,
          isAuthenticated: true,
        ));
        return;
      }
    }

    _log('Peer is not paired. Enter pairing code to connect.');
    _eventController.add(PeerStateEvent(
      isConnected: true,
      peerName: peerName,
      isPaired: false,
      isAuthenticated: false,
    ));
  }

  Future<void> _onAuth(Map<String, dynamic> m) async {
    final sigC = List<int>.from(m['sig'] as List);
    final knownDevice = await _db.findDeviceById(_pendingPeerId ?? '');

    if (knownDevice != null) {
      final transcript = utf8.encode(
          'hotshare/v2|${knownDevice.id}|${_identity!.deviceId}|${_hex(_nonceC!)}|${_hex(_nonceS!)}|auth');

      final valid = await DeviceIdentity.verify(
        message: transcript,
        signature: sigC,
        publicKeyBytes: knownDevice.publicKey,
      );

      if (valid) {
        _isAuthenticated = true;
        _log('Client authentication verified: ${knownDevice.name}');
        _eventController.add(PeerStateEvent(
          isConnected: true,
          peerName: knownDevice.name,
          isPaired: true,
          isAuthenticated: true,
        ));
      }
    }
  }

  // ---------------------------------------------------------------------------
  // One-Time Pairing Logic
  // ---------------------------------------------------------------------------

  void _openPairingWindow() {
    _pairingCode = PairingSecurity.generatePairingCode();
    _pairingExpiry = DateTime.now().add(const Duration(seconds: 60));
    _pairingAttempts = 0;

    final secret = PairingSecurity.generatePairSecret();
    final qrPayload =
        'hotshare://pair?v=2&id=${_identity?.deviceId}&code=$_pairingCode&s=$secret';

    _log('Pairing window open (60s). Code: $_pairingCode');
    _eventController.add(PairingWindowOpenedEvent(
      code: _pairingCode!,
      qrPayload: qrPayload,
      expiresAt: _pairingExpiry!,
    ));
  }

  void _submitPairingCode(String code) {
    final ws = _socket;
    if (ws == null || _nonceC == null || _nonceS == null || _identity == null) {
      _log('Cannot submit pairing code: not connected to peer');
      return;
    }

    final proof = PairingSecurity.computePairingProof(
      code: code.trim(),
      nonceC: _nonceC!,
      nonceS: _nonceS!,
      pubKeyC: _identity!.publicKeyBytes,
    );

    final myName = (_localDeviceName != null && _localDeviceName!.isNotEmpty)
        ? _localDeviceName!
        : (Platform.isWindows ? 'Windows PC' : 'Android Phone');

    ws.add(jsonEncode({
      't': 'pair_request',
      'proof': proof,
      'pubKey': _identity!.publicKeyBytes,
      'name': myName,
      'platform': Platform.operatingSystem,
    }));
    _log('Pairing request submitted with code');
  }

  Future<void> _onPairRequest(Map<String, dynamic> m) async {
    final ws = _socket;
    if (ws == null || _identity == null) return;

    if (_pairingCode == null ||
        _pairingExpiry == null ||
        DateTime.now().isAfter(_pairingExpiry!)) {
      ws.add(jsonEncode({'t': 'pair_reject', 'reason': 'window_closed'}));
      _log('Pairing rejected: window expired');
      return;
    }

    if (_pairingAttempts >= 3) {
      ws.add(jsonEncode({'t': 'pair_reject', 'reason': 'max_attempts'}));
      _log('Pairing rejected: max attempts exceeded');
      return;
    }

    final receivedProof = m['proof'] as String;
    final peerPubKey = List<int>.from(m['pubKey'] as List);
    final peerName = m['name'] as String;
    final peerPlatform = m['platform'] as String;

    final expectedProof = PairingSecurity.computePairingProof(
      code: _pairingCode!,
      nonceC: _nonceC!,
      nonceS: _nonceS!,
      pubKeyC: peerPubKey,
    );

    if (receivedProof == expectedProof) {
      _pendingPeerPubKey = peerPubKey;
      _pendingPeerName = peerName;
      _pendingPeerPlatform = peerPlatform;
      _pendingPeerId = _base32(crypto.sha256.convert(peerPubKey).bytes.sublist(0, 16));

      final sas = PairingSecurity.deriveSasWords(
        pubKeyC: peerPubKey,
        pubKeyS: _identity!.publicKeyBytes,
        nonceC: _nonceC!,
        nonceS: _nonceS!,
      );

      final myName = (_localDeviceName != null && _localDeviceName!.isNotEmpty)
          ? _localDeviceName!
          : (Platform.isWindows ? 'Windows PC' : 'Android Phone');

      ws.add(jsonEncode({
        't': 'pair_verify',
        'sas': sas,
        'pubKey': _identity!.publicKeyBytes,
        'name': myName,
        'platform': Platform.operatingSystem,
      }));

      _log('Verification phrase derived: ${sas.join(' - ')}');
      _eventController.add(PairingVerificationRequiredEvent(
        sasWords: sas,
        peerName: peerName,
        peerId: _pendingPeerId!,
      ));
    } else {
      _pairingAttempts++;
      _log('Pairing proof mismatch (attempt $_pairingAttempts/3)');
      ws.add(jsonEncode({'t': 'pair_reject', 'reason': 'invalid_code'}));
    }
  }

  void _onPairVerify(Map<String, dynamic> m) {
    final peerPubKey = List<int>.from(m['pubKey'] as List);
    final peerName = m['name'] as String;
    final peerPlatform = m['platform'] as String;
    final sas = List<String>.from(m['sas'] as List);

    _pendingPeerPubKey = peerPubKey;
    _pendingPeerName = peerName;
    _pendingPeerPlatform = peerPlatform;
    _pendingPeerId = _base32(crypto.sha256.convert(peerPubKey).bytes.sublist(0, 16));

    _log('Verification phrase received: ${sas.join(' - ')}');
    _eventController.add(PairingVerificationRequiredEvent(
      sasWords: sas,
      peerName: peerName,
      peerId: _pendingPeerId!,
    ));
  }

  Future<void> _confirmPairing(bool isConfirmed) async {
    final ws = _socket;
    if (ws == null || !isConfirmed || _pendingPeerPubKey == null) {
      _socket?.add(jsonEncode({'t': 'pair_confirm', 'ok': false}));
      return;
    }

    ws.add(jsonEncode({'t': 'pair_confirm', 'ok': true}));
    await _finalizePairing();
  }

  Future<void> _onPairConfirm(Map<String, dynamic> m) async {
    if (m['ok'] == true) {
      await _finalizePairing();
    } else {
      _log('Pairing rejected by peer');
      _eventController.add(const PairingCompletedEvent(
        success: false,
        peerName: '',
        error: 'Pairing rejected',
      ));
    }
  }

  Future<void> _finalizePairing() async {
    if (_pendingPeerPubKey == null || _pendingPeerId == null) return;

    final peerId = _pendingPeerId!;
    final peerName = _pendingPeerName ?? 'Paired Device';

    await _db.upsertDevice(DevicesCompanion(
      id: drift.Value(peerId),
      name: drift.Value(peerName),
      platform: drift.Value(_pendingPeerPlatform ?? 'unknown'),
      publicKey: drift.Value(Uint8List.fromList(_pendingPeerPubKey!)),
      pairedAt: drift.Value(DateTime.now()),
      autoAccept: const drift.Value(true),
      revoked: const drift.Value(false),
    ));

    _isAuthenticated = true;
    _pairingCode = null;
    _pairingExpiry = null;
    _pendingPeerPubKey = null;

    _log('Pairing successful with $peerName!');
    _eventController.add(PairingCompletedEvent(
      success: true,
      peerName: peerName,
    ));

    _eventController.add(PeerStateEvent(
      isConnected: true,
      peerName: peerName,
      isPaired: true,
      isAuthenticated: true,
    ));
  }

  Future<void> _revokeDevice(String deviceId) async {
    await _db.revokeDevice(deviceId);
    _log('Device revoked: $deviceId');

    final ws = _socket;
    if (ws != null) {
      try {
        ws.add(jsonEncode({
          't': 'revoke',
          'deviceId': _identity?.deviceId,
        }));
      } catch (_) {}
    }

    _isAuthenticated = false;
    _eventController.add(const PeerStateEvent(
      isConnected: true,
      peerName: '',
      isPaired: false,
      isAuthenticated: false,
    ));
    _disconnect();
  }

  // ---------------------------------------------------------------------------
  // Protocol Handling
  // ---------------------------------------------------------------------------

  Future<void> _onData(dynamic data, String peer) async {
    _lastActivityTime = DateTime.now();

    try {
      if (data is String) {
        final m = jsonDecode(data) as Map<String, dynamic>;
        switch (m['t']) {
          case 'hello':
            await _onHello(m);
          case 'hello_ack':
            await _onHelloAck(m);
          case 'auth':
            await _onAuth(m);
          case 'pair_request':
            await _onPairRequest(m);
          case 'pair_verify':
            _onPairVerify(m);
          case 'pair_confirm':
            await _onPairConfirm(m);
          case 'ping':
            _socket?.add(jsonEncode({'t': 'pong', 'ts': m['ts']}));
          case 'pong':
            break;
          case 'text':
            _log('$peer says: ${m['body']}');
          case 'offer':
            await _onOffer(m);
          case 'accept':
            final offset = (m['offset'] as num?)?.toInt() ?? 0;
            _completeAccept(offset);
          case 'reject':
            final reason = m['reason'] as String?;
            if (reason == 'unauthenticated') {
              _isAuthenticated = false;
              _eventController.add(const PeerStateEvent(
                isConnected: true,
                peerName: '',
                isPaired: false,
                isAuthenticated: false,
              ));
            }
            _completeAccept(null);
          case 'revoke':
            final revokingPeerId = m['deviceId'] as String?;
            if (revokingPeerId != null) {
              await _db.revokeDevice(revokingPeerId);
            }
            _isAuthenticated = false;
            _log('Peer revoked pairing. Resetting trust.');
            _eventController.add(const PeerStateEvent(
              isConnected: true,
              peerName: '',
              isPaired: false,
              isAuthenticated: false,
            ));
          case 'progress':
            _onProgress(m);
          case 'done':
            await _onDone(m);
          case 'result':
            _onResult(m);
          case 'cancel':
            await _abortIncoming('sender cancelled');
        }
      } else if (data is List<int>) {
        _onChunk(data);
      }
    } catch (e) {
      _log('Protocol handling error: $e');
    }
  }

  void _completeAccept(int? offset) {
    final w = _acceptWaiter;
    if (w != null && !w.isCompleted) w.complete(offset);
  }

  // ---------------------------------------------------------------------------
  // Receiving Pipeline
  // ---------------------------------------------------------------------------

  Future<void> _onOffer(Map<String, dynamic> m) async {
    final ws = _socket;
    if (ws == null) return;

    final id = m['id'] as String;
    final isBenchmark = m['benchmark'] == true;

    if (isBenchmark) {
      _benchmarkIncomingId = id;
      _benchmarkExpectedBytes = (m['size'] as num).toInt();
      _benchmarkReceivedBytes = 0;
      _benchmarkStartTime = DateTime.now();
      _log('Receiving benchmark stream (${formatBytes(_benchmarkExpectedBytes)})');
      ws.add(jsonEncode({'t': 'accept', 'id': id}));
      return;
    }

    if (_pauseReceiving) {
      ws.add(jsonEncode({'t': 'reject', 'id': id, 'reason': 'paused'}));
      _log('Silently declined incoming file offer: Pause Receiving is enabled');
      return;
    }

    if (!_isAuthenticated && !isBenchmark) {
      ws.add(jsonEncode({'t': 'reject', 'id': id, 'reason': 'unauthenticated'}));
      _log('Rejected offer from unauthenticated peer');
      return;
    }

    if (_incoming != null) {
      ws.add(jsonEncode({'t': 'reject', 'id': id, 'reason': 'busy'}));
      return;
    }

    final rawRelPath = (m['relPath'] as String?) ?? (m['name'] as String);
    final effectiveRelPath = sanitizeRelativePath(rawRelPath);
    final displayName = effectiveRelPath.replaceAll('\\', '/');
    final size = (m['size'] as num).toInt();

    if (!_autoAccept) {
      _pendingIncomingOffers[id] = m;
      _log('Incoming file offer received: $displayName (${formatBytes(size)}) - waiting for user acceptance');
      _eventController.add(IncomingTransferOfferEvent(
        transferId: id,
        fileName: displayName,
        size: size,
        peerName: _pendingPeerName ?? 'Device',
      ));
      return;
    }

    await _processAcceptedOffer(m);
  }

  Future<void> _respondToOffer(String id, bool accept) async {
    final m = _pendingIncomingOffers.remove(id);
    final ws = _socket;
    if (ws == null || m == null) return;

    if (!accept) {
      ws.add(jsonEncode({'t': 'reject', 'id': id, 'reason': 'declined'}));
      _log('User declined transfer offer: $id');
      return;
    }

    await _processAcceptedOffer(m);
  }

  Future<void> _processAcceptedOffer(Map<String, dynamic> m) async {
    final ws = _socket;
    if (ws == null) return;

    final id = m['id'] as String;
    final rawRelPath = (m['relPath'] as String?) ?? (m['name'] as String);
    final effectiveRelPath = sanitizeRelativePath(rawRelPath);
    final displayName = effectiveRelPath.replaceAll('\\', '/');
    final size = (m['size'] as num).toInt();
    final dir = await StorageResolver.resolveDestinationDirectory(fileName: displayName);
    
    final candidateFile = File('${dir.path}${Platform.pathSeparator}$effectiveRelPath');
    if (!await candidateFile.parent.exists()) {
      await candidateFile.parent.create(recursive: true);
    }

    int resumeOffset = 0;
    File file;
    if (await candidateFile.exists()) {
      final existingLength = await candidateFile.length();
      if (existingLength > 0 && existingLength < size) {
        resumeOffset = existingLength;
        file = candidateFile;
        _log('Resuming partial incoming file $displayName at offset ${formatBytes(resumeOffset)}');
      } else {
        file = createUniqueFile(candidateFile.parent, candidateFile.uri.pathSegments.last);
      }
    } else {
      file = candidateFile;
    }

    final kind = StorageResolver.classifyFileKind(displayName);
    await _db.insertTransfer(TransfersCompanion(
      id: drift.Value(id),
      peerId: drift.Value(_pendingPeerId ?? 'peer'),
      direction: const drift.Value('in'),
      name: drift.Value(displayName),
      size: drift.Value(size),
      kind: drift.Value(kind),
      status: const drift.Value('transferring'),
      bytesDone: drift.Value(resumeOffset),
      localPath: drift.Value(file.path),
      startedAt: drift.Value(DateTime.now()),
    ));

    final sink = file.openWrite(mode: resumeOffset > 0 ? FileMode.append : FileMode.write);
    final inc = IncomingTransfer(
      id: id,
      name: displayName,
      size: size,
      file: file,
      sink: sink,
      offset: resumeOffset,
    );

    _incoming = inc;
    _recvStartTime = DateTime.now();
    _lastRecvThrottleTime = DateTime.now();

    _log('Receiving $displayName (${formatBytes(size)})');
    AndroidForegroundServiceManager.updateNotification(
      title: 'Receiving $displayName',
      text: formatBytes(size),
    );

    _eventController.add(TransferProgressEvent(
      id: id,
      name: displayName,
      bytesDone: resumeOffset,
      totalBytes: size,
      progress: size == 0 ? 1.0 : (resumeOffset / size).clamp(0.0, 1.0),
      speedBytesPerSec: 0,
      isSending: false,
    ));

    ws.add(jsonEncode({'t': 'accept', 'id': id, 'offset': resumeOffset}));
  }

  void _onChunk(List<int> data) {
    _lastActivityTime = DateTime.now();

    if (_benchmarkIncomingId != null) {
      _benchmarkReceivedBytes += data.length;
      return;
    }

    final inc = _incoming;
    if (inc == null) return;

    inc.addChunk(data);

    if (inc.received - inc.lastAck >= kAckEvery) {
      inc.lastAck = inc.received;
      _socket?.add(jsonEncode(
        {'t': 'progress', 'id': inc.id, 'bytes': inc.received},
      ));
    }

    final now = DateTime.now();
    if (_lastRecvThrottleTime == null ||
        now.difference(_lastRecvThrottleTime!) >= kProgressThrottleInterval) {
      final elapsedSec =
          now.difference(_recvStartTime ?? now).inMilliseconds / 1000.0;
      final speed = elapsedSec > 0 ? (inc.received / elapsedSec) : 0.0;
      _lastRecvThrottleTime = now;

      _eventController.add(TransferProgressEvent(
        id: inc.id,
        name: inc.name,
        bytesDone: inc.received,
        totalBytes: inc.size,
        progress: inc.size == 0 ? 1.0 : (inc.received / inc.size).clamp(0.0, 1.0),
        speedBytesPerSec: speed,
        isSending: false,
      ));
    }
  }

  Future<void> _onDone(Map<String, dynamic> m) async {
    final id = m['id'] as String;

    if (_benchmarkIncomingId != null && _benchmarkIncomingId == id) {
      final duration =
          DateTime.now().difference(_benchmarkStartTime ?? DateTime.now());
      final durationSec = duration.inMilliseconds / 1000.0;
      final mb = _benchmarkReceivedBytes / (1024 * 1024);
      final mbPerSec = durationSec > 0 ? (mb / durationSec) : 0.0;

      _log('Benchmark complete: ${mbPerSec.toStringAsFixed(1)} MB/s (${formatBytes(_benchmarkReceivedBytes)} in ${durationSec.toStringAsFixed(2)}s)');
      _socket?.add(jsonEncode({'t': 'result', 'id': id, 'ok': true}));

      _eventController.add(BenchmarkResultEvent(
        mbPerSec: mbPerSec,
        totalBytes: _benchmarkReceivedBytes,
        duration: duration,
        isSender: false,
      ));

      _benchmarkIncomingId = null;
      return;
    }

    final inc = _incoming;
    if (inc == null) return;
    _incoming = null;

    final expectedSha = m['sha256'] as String?;
    final actualSha = inc.finalizeChecksum();

    var ok = false;
    String? errorReason;
    try {
      await inc.sink.flush();
      await inc.sink.close();
      ok = inc.received == inc.size;
      if (ok && expectedSha != null && actualSha != null) {
        if (expectedSha != actualSha) {
          ok = false;
          errorReason = 'SHA-256 integrity mismatch';
          _log('SHA-256 mismatch for ${inc.name}! Expected: $expectedSha, got: $actualSha');
        } else {
          _log('SHA-256 integrity verified for ${inc.name}');
        }
      }
    } catch (e) {
      _log('Write error on finish: $e');
      errorReason = e.toString();
    }

    if (!ok) {
      errorReason ??= 'Size mismatch: got ${inc.received} of ${inc.size}';
      try {
        if (await inc.file.exists()) {
          await inc.file.delete();
        }
      } catch (_) {}
    }

    _socket?.add(jsonEncode({'t': 'result', 'id': inc.id, 'ok': ok}));

    final durationSec = inc.received > 0 && _recvStartTime != null
        ? DateTime.now().difference(_recvStartTime!).inMilliseconds / 1000.0
        : 1.0;
    final avgSpeed = durationSec > 0 ? (inc.received / durationSec).round() : 0;

    await _db.completeTransfer(
      inc.id,
      status: ok ? 'done' : 'failed',
      localPath: ok ? inc.file.path : null,
      error: ok ? null : errorReason,
      avgSpeed: avgSpeed,
    );

    if (ok) {
      await StorageResolver.scanMedia(inc.file.path);
    }

    _eventController.add(TransferCompletedEvent(
      id: inc.id,
      name: inc.name,
      filePath: ok ? inc.file.path : null,
      size: inc.size,
      isSending: false,
      success: ok,
      error: ok ? null : errorReason,
    ));

    AndroidForegroundServiceManager.updateNotification(
      title: 'HotShare is ready',
      text: ok ? 'Received ${inc.name}' : 'Transfer failed: $errorReason',
    );

    _log(ok
        ? 'Saved ${inc.name} (${formatBytes(inc.size)})'
        : 'Failed ${inc.name}: $errorReason');
  }

  Future<void> _abortIncoming(String reason) async {
    _benchmarkIncomingId = null;
    final inc = _incoming;
    if (inc == null) return;
    _incoming = null;
    try {
      await inc.sink.close();
      if (await inc.file.exists()) await inc.file.delete();
    } catch (_) {}
    _eventController.add(TransferCompletedEvent(
      id: inc.id,
      name: inc.name,
      size: inc.size,
      isSending: false,
      success: false,
      error: reason,
    ));
    AndroidForegroundServiceManager.updateNotification(
      title: 'HotShare is ready',
      text: 'Transfer aborted',
    );
    _log('Receive cancelled: $reason');
  }

  // ---------------------------------------------------------------------------
  // Sending Pipeline
  // ---------------------------------------------------------------------------

  void _onProgress(Map<String, dynamic> m) {
    _acked = (m['bytes'] as num).toInt();
    final w = _creditWaiter;
    if (w != null && !w.isCompleted) w.complete();
  }

  void _onResult(Map<String, dynamic> m) {
    final w = _resultWaiter;
    if (w != null && !w.isCompleted) w.complete(m['ok'] == true);
  }

  Future<void> _sendFiles(List<String> paths) async {
    final payloads = await expandPaths(paths);
    for (final payload in payloads) {
      if (_socket == null) break;
      await _sendFilePayload(payload);
    }
  }

  Future<void> _sendFilePayload(FilePayload payload) async {
    final ws = _socket;
    if (ws == null) {
      _log('Cannot send: not connected');
      return;
    }
    if (!_isAuthenticated) {
      _log('Cannot send: device is not paired/authenticated');
      return;
    }
    if (_sending) {
      _log('Another transfer is already in progress');
      return;
    }

    final file = payload.file;
    if (!await file.exists()) {
      _log('File does not exist: ${file.path}');
      return;
    }

    final size = payload.size;
    final name = payload.relativePath;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    _currentSendingId = id;

    final kind = StorageResolver.classifyFileKind(name);
    await _db.insertTransfer(TransfersCompanion(
      id: drift.Value(id),
      peerId: drift.Value(_pendingPeerId ?? 'peer'),
      direction: const drift.Value('out'),
      name: drift.Value(name),
      size: drift.Value(size),
      kind: drift.Value(kind),
      status: const drift.Value('transferring'),
      bytesDone: const drift.Value(0),
      localPath: drift.Value(file.path),
      startedAt: drift.Value(DateTime.now()),
    ));

    _sending = true;
    _acked = 0;

    _log('Offering $name (${formatBytes(size)})');
    AndroidForegroundServiceManager.updateNotification(
      title: 'Sending $name',
      text: formatBytes(size),
    );

    _eventController.add(TransferProgressEvent(
      id: id,
      name: name,
      bytesDone: 0,
      totalBytes: size,
      progress: 0.0,
      speedBytesPerSec: 0,
      isSending: true,
    ));

    try {
      _acceptWaiter = Completer<int?>();
      ws.add(jsonEncode({
        't': 'offer',
        'id': id,
        'name': name,
        'relPath': name,
        'size': size,
      }));

      final acceptedOffset = await _acceptWaiter!.future
          .timeout(const Duration(seconds: 15), onTimeout: () => null);

      if (acceptedOffset == null) {
        _log('Receiver declined $name');
        _eventController.add(TransferCompletedEvent(
          id: id,
          name: name,
          size: size,
          isSending: true,
          success: false,
          error: 'Receiver declined',
        ));
        return;
      }

      final startTime = DateTime.now();
      var lastThrottle = DateTime.now();
      var sent = acceptedOffset;

      DigestSink? shaAcc;
      ByteConversionSink? shaHasher;
      if (acceptedOffset == 0) {
        shaAcc = DigestSink();
        shaHasher = crypto.sha256.startChunkedConversion(shaAcc);
      }

      final raf = await file.open(mode: FileMode.read);
      if (acceptedOffset > 0) {
        await raf.setPosition(acceptedOffset);
        _log('Resuming $name from offset ${formatBytes(acceptedOffset)}');
      }
      try {
        while (sent < size) {
          if (!_sending) throw 'Transfer cancelled';
          if (_socket != ws) throw 'Connection lost during transfer';

          final toRead = (size - sent) < kChunkSize ? (size - sent) : kChunkSize;
          final chunk = await raf.read(toRead);
          if (chunk.isEmpty) break;

          ws.add(chunk);
          sent += chunk.length;
          shaHasher?.add(chunk);

          // Yield to event loop periodically so Flutter UI paints at 60/120fps without skipping frames
          if (sent % (kChunkSize * 8) == 0) {
            await Future<void>.delayed(Duration.zero);
          }

          while (sent - _acked > kWindow) {
            _creditWaiter = Completer<void>();
            await _creditWaiter!.future.timeout(const Duration(seconds: 20));
            if (!_sending) throw 'Transfer cancelled';
            if (_socket != ws) throw 'Connection lost waiting for credit';
          }

          final now = DateTime.now();
          if (now.difference(lastThrottle) >= kProgressThrottleInterval) {
            final elapsed = now.difference(startTime).inMilliseconds / 1000.0;
            final speed = elapsed > 0 ? (sent / elapsed) : 0.0;
            lastThrottle = now;

            _eventController.add(TransferProgressEvent(
              id: id,
              name: name,
              bytesDone: sent,
              totalBytes: size,
              progress: size == 0 ? 1.0 : (sent / size).clamp(0.0, 1.0),
              speedBytesPerSec: speed,
              isSending: true,
            ));
          }
        }
      } finally {
        await raf.close();
      }

      shaHasher?.close();
      final shaHex = shaAcc?.value?.toString();

      _resultWaiter = Completer<bool>();
      final donePayload = <String, dynamic>{
        't': 'done',
        'id': id,
      };
      if (shaHex != null) {
        donePayload['sha256'] = shaHex;
      }
      ws.add(jsonEncode(donePayload));

      final ok = await _resultWaiter!.future
          .timeout(const Duration(seconds: 30), onTimeout: () => false);

      final durationSec = sent > 0
          ? DateTime.now().difference(startTime).inMilliseconds / 1000.0
          : 1.0;
      final avgSpeed = durationSec > 0 ? (sent / durationSec).round() : 0;

      await _db.completeTransfer(
        id,
        status: ok ? 'done' : 'failed',
        localPath: file.path,
        error: ok ? null : 'Integrity verification failed',
        avgSpeed: avgSpeed,
      );

      _eventController.add(TransferCompletedEvent(
        id: id,
        name: name,
        size: size,
        isSending: true,
        success: ok,
        error: ok ? null : 'Integrity verification failed',
      ));

      AndroidForegroundServiceManager.updateNotification(
        title: 'HotShare is ready',
        text: ok ? 'Sent $name' : 'Failed to send $name',
      );

      _log(ok
          ? 'Delivered $name (${formatBytes(size)})'
          : 'Delivery verification failed for $name');
    } catch (e) {
      _log('Send error on $name: $e');
      _eventController.add(TransferCompletedEvent(
        id: id,
        name: name,
        filePath: file.path,
        size: size,
        isSending: true,
        success: false,
        error: e.toString(),
      ));
    } finally {
      _sending = false;
      _currentSendingId = null;
    }
  }

  // ---------------------------------------------------------------------------
  // Benchmark Pipeline
  // ---------------------------------------------------------------------------

  Future<void> _runBenchmark(int sizeMb) async {
    final ws = _socket;
    if (ws == null) {
      _log('Benchmark cannot run: not connected');
      return;
    }
    if (_sending) {
      _log('Another transfer is active');
      return;
    }

    final totalBytes = sizeMb * 1024 * 1024;
    final id = 'bench_${DateTime.now().millisecondsSinceEpoch}';

    _sending = true;
    _acked = 0;

    _log('Starting network benchmark ($sizeMb MB)...');

    try {
      _acceptWaiter = Completer<int?>();
      ws.add(jsonEncode({
        't': 'offer',
        'id': id,
        'name': 'benchmark.bin',
        'size': totalBytes,
        'benchmark': true,
      }));

      final acceptedOffset = await _acceptWaiter!.future
          .timeout(const Duration(seconds: 10), onTimeout: () => null);

      if (acceptedOffset == null) {
        _log('Peer rejected benchmark request');
        return;
      }

      final startTime = DateTime.now();
      var sent = 0;
      final buffer = Uint8List(kChunkSize);

      while (sent < totalBytes) {
        if (_socket != ws) throw 'Connection lost';
        ws.add(buffer);
        sent += buffer.length;

        while (sent - _acked > kWindow) {
          _creditWaiter = Completer<void>();
          await _creditWaiter!.future.timeout(const Duration(seconds: 15));
          if (_socket != ws) throw 'Connection lost';
        }
      }

      _resultWaiter = Completer<bool>();
      ws.add(jsonEncode({'t': 'done', 'id': id}));

      final ok = await _resultWaiter!.future
          .timeout(const Duration(seconds: 15), onTimeout: () => false);

      final duration = DateTime.now().difference(startTime);
      final durationSec = duration.inMilliseconds / 1000.0;
      final mbPerSec = durationSec > 0 ? (sizeMb / durationSec) : 0.0;

      if (ok) {
        _log('Benchmark result: ${mbPerSec.toStringAsFixed(1)} MB/s ($sizeMb MB in ${durationSec.toStringAsFixed(2)}s)');
        _eventController.add(BenchmarkResultEvent(
          mbPerSec: mbPerSec,
          totalBytes: totalBytes,
          duration: duration,
          isSender: true,
        ));
      }
    } catch (e) {
      _log('Benchmark failed: $e');
    } finally {
      _sending = false;
    }
  }

  void _sendText(String text) {
    final ws = _socket;
    if (ws == null) {
      _log('Not connected');
      return;
    }
    ws.add(jsonEncode({'t': 'text', 'body': text}));
    _log('You: $text');
  }

  void _cancelTransfer(String transferId) {
    if (_currentSendingId == transferId || transferId.isEmpty) {
      _sending = false;
      if (_acceptWaiter != null && !_acceptWaiter!.isCompleted) {
        _acceptWaiter!.complete(null);
      }
      if (_creditWaiter != null && !_creditWaiter!.isCompleted) {
        _creditWaiter!.complete();
      }
      final ws = _socket;
      if (ws != null) {
        try {
          ws.add(jsonEncode({'t': 'cancel', 'id': transferId}));
        } catch (_) {}
      }
    }
    if (_incoming != null && (_incoming!.id == transferId || transferId.isEmpty)) {
      _abortIncoming('Transfer cancelled by user');
    }
    _eventController.add(TransferCompletedEvent(
      id: transferId,
      name: '',
      size: 0,
      isSending: true,
      success: false,
      error: 'Transfer cancelled by user',
    ));
    _log('Transfer cancelled: $transferId');
  }

  static String _hex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String _base32(List<int> bytes) {
    const chars = 'abcdefghijklmnopqrstuvwxyz234567';
    final output = StringBuffer();
    int buffer = 0;
    int bitsLeft = 0;

    for (final b in bytes) {
      buffer = (buffer << 8) | (b & 0xFF);
      bitsLeft += 8;
      while (bitsLeft >= 5) {
        final index = (buffer >> (bitsLeft - 5)) & 0x1F;
        bitsLeft -= 5;
        output.write(chars[index]);
      }
    }
    if (bitsLeft > 0) {
      final index = (buffer << (5 - bitsLeft)) & 0x1F;
      output.write(chars[index]);
    }
    return output.toString();
  }

  void dispose() {
    _disconnect();
    _eventController.close();
    if (_ownsDb) {
      _db.close();
    }
  }
}
