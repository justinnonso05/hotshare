import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:drift/drift.dart' as drift;

import '../../data/db/app_database.dart';
import '../constants/network_constants.dart';
import '../platform/android_foreground.dart';
import '../security/identity.dart';
import '../security/pairing.dart';
import '../storage/storage_helper.dart';
import '../transfer/incoming_transfer.dart';
import '../utils/formatters.dart';
import 'engine_api.dart';

/// Pure Dart implementation of the HotShare engine.
/// Exposes a stream of [EngineEvent]s and receives [EngineCommand]s.
class HotShareEngine {
  final StreamController<EngineEvent> _eventController =
      StreamController<EngineEvent>.broadcast();

  Stream<EngineEvent> get events => _eventController.stream;

  final AppDatabase _db = AppDatabase();
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
  Completer<bool>? _acceptWaiter;
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

  HotShareEngine() {
    _initIdentity();
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
    }
  }

  void _log(String msg) {
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
          final ws = await WebSocketTransformer.upgrade(
            request,
            compression: CompressionOptions.compressionOff,
          );
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
    final cleanHost = host.trim();
    if (cleanHost.isEmpty) {
      if (!isAutoRetry) _log('Host address cannot be empty');
      return;
    }
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
    }
  }

  void _attach(WebSocket ws, String peer, {required bool isServer}) {
    _socket?.close();
    ws.pingInterval = const Duration(seconds: 10);
    _socket = ws;
    _isAuthenticated = false;
    _lastActivityTime = DateTime.now();

    _eventController.add(PeerStateEvent(
      isConnected: true,
      peerName: peer,
      isPaired: false,
      isAuthenticated: false,
    ));
    _log('Socket connected ($peer)');

    _startHeartbeat(ws);

    // If client, send hello
    if (!isServer) {
      _sendHello(ws);
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
    if (!Platform.isAndroid && _autoReconnect && _targetHost != null) {
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

    final deviceName = Platform.isWindows ? 'Windows PC' : 'Android Phone';
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

    final knownDevice = await _db.findDeviceById(peerId);
    final isPaired = knownDevice != null && !knownDevice.revoked;

    if (isPaired) {
      final transcript = utf8.encode(
          'hotshare/v2|$peerId|${_identity!.deviceId}|${_hex(nonceC)}|${_hex(nonceS)}');
      final sigS = await _identity!.sign(transcript);

      ws.add(jsonEncode({
        't': 'hello_ack',
        'v': 2,
        'deviceId': _identity!.deviceId,
        'name': Platform.isAndroid ? 'Android Phone' : 'Windows PC',
        'nonce': nonceS,
        'sig': sigS,
        'known': true,
      }));
    } else {
      _pendingPeerId = peerId;
      _pendingPeerName = peerName;
      _pendingPeerPlatform = peerPlatform;
      _pendingPeerPubKey = peerPubKey;

      ws.add(jsonEncode({
        't': 'hello_ack',
        'v': 2,
        'deviceId': _identity!.deviceId,
        'name': Platform.isAndroid ? 'Android Phone' : 'Windows PC',
        'nonce': nonceS,
        'known': false,
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
    if (ws == null || _identity == null) return;

    final peerId = m['deviceId'] as String;
    final peerName = m['name'] as String;
    final nonceS = List<int>.from(m['nonce'] as List);
    _nonceS = nonceS;
    final isKnown = m['known'] == true;

    if (isKnown) {
      final knownDevice = await _db.findDeviceById(peerId);
      if (knownDevice != null && !knownDevice.revoked) {
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

    ws.add(jsonEncode({
      't': 'pair_request',
      'proof': proof,
      'pubKey': _identity!.publicKeyBytes,
      'name': Platform.isWindows ? 'Windows PC' : 'Android Phone',
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

      ws.add(jsonEncode({
        't': 'pair_verify',
        'sas': sas,
        'pubKey': _identity!.publicKeyBytes,
        'name': Platform.isAndroid ? 'Android Phone' : 'Windows PC',
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

    await _db.upsertDevice(DevicesCompanion(
      id: drift.Value(_pendingPeerId!),
      name: drift.Value(_pendingPeerName ?? 'Paired Device'),
      platform: drift.Value(_pendingPeerPlatform ?? 'unknown'),
      publicKey: drift.Value(Uint8List.fromList(_pendingPeerPubKey!)),
      pairedAt: drift.Value(DateTime.now()),
      autoAccept: const drift.Value(true),
      revoked: const drift.Value(false),
    ));

    _isAuthenticated = true;
    _pairingCode = null;
    _pairingExpiry = null;

    _log('Pairing successful with $_pendingPeerName!');
    _eventController.add(PairingCompletedEvent(
      success: true,
      peerName: _pendingPeerName ?? '',
    ));

    _eventController.add(PeerStateEvent(
      isConnected: true,
      peerName: _pendingPeerName ?? '',
      isPaired: true,
      isAuthenticated: true,
    ));
  }

  Future<void> _revokeDevice(String deviceId) async {
    await _db.revokeDevice(deviceId);
    _log('Device revoked: $deviceId');
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
            _completeAccept(true);
          case 'reject':
            _completeAccept(false);
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

  void _completeAccept(bool v) {
    final w = _acceptWaiter;
    if (w != null && !w.isCompleted) w.complete(v);
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

    if (!_isAuthenticated && !isBenchmark) {
      ws.add(jsonEncode({'t': 'reject', 'id': id, 'reason': 'unauthenticated'}));
      _log('Rejected offer from unauthenticated peer');
      return;
    }

    if (_incoming != null) {
      ws.add(jsonEncode({'t': 'reject', 'id': id, 'reason': 'busy'}));
      return;
    }

    final name = sanitizeFileName(m['name'] as String);
    final size = (m['size'] as num).toInt();
    final dir = await getHotShareSaveDirectory();
    final file = createUniqueFile(dir, name);

    final inc = IncomingTransfer(
      id: id,
      name: name,
      size: size,
      file: file,
      sink: file.openWrite(),
    );

    _incoming = inc;
    _recvStartTime = DateTime.now();
    _lastRecvThrottleTime = DateTime.now();

    _log('Receiving $name (${formatBytes(size)})');
    AndroidForegroundServiceManager.updateNotification(
      title: 'Receiving $name',
      text: formatBytes(size),
    );

    _eventController.add(TransferProgressEvent(
      id: id,
      name: name,
      bytesDone: 0,
      totalBytes: size,
      progress: 0.0,
      speedBytesPerSec: 0,
      isSending: false,
    ));

    ws.add(jsonEncode({'t': 'accept', 'id': id}));
  }

  void _onChunk(List<int> data) {
    _lastActivityTime = DateTime.now();

    if (_benchmarkIncomingId != null) {
      _benchmarkReceivedBytes += data.length;
      return;
    }

    final inc = _incoming;
    if (inc == null) return;

    inc.sink.add(data);
    inc.received += data.length;

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

    var ok = false;
    try {
      await inc.sink.flush();
      await inc.sink.close();
      ok = inc.received == inc.size;
    } catch (e) {
      _log('Write error on finish: $e');
    }

    _socket?.add(jsonEncode({'t': 'result', 'id': inc.id, 'ok': ok}));

    _eventController.add(TransferCompletedEvent(
      id: inc.id,
      name: inc.name,
      filePath: ok ? inc.file.path : null,
      size: inc.size,
      isSending: false,
      success: ok,
      error: ok ? null : 'Size mismatch: got ${inc.received} of ${inc.size}',
    ));

    AndroidForegroundServiceManager.updateNotification(
      title: 'HotShare is ready',
      text: ok ? 'Received ${inc.name}' : 'Transfer failed',
    );

    _log(ok
        ? 'Saved ${inc.name} (${formatBytes(inc.size)})'
        : 'Failed ${inc.name}: size mismatch');
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
    for (final path in paths) {
      await _sendFile(path);
    }
  }

  Future<void> _sendFile(String path) async {
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

    final file = File(path);
    if (!await file.exists()) {
      _log('File does not exist: $path');
      return;
    }

    final size = await file.length();
    final name = path.split(RegExp(r'[\\/]')).last;
    final id = DateTime.now().microsecondsSinceEpoch.toString();

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
      _acceptWaiter = Completer<bool>();
      ws.add(jsonEncode({'t': 'offer', 'id': id, 'name': name, 'size': size}));

      final accepted = await _acceptWaiter!.future
          .timeout(const Duration(seconds: 15), onTimeout: () => false);

      if (!accepted) {
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
      var sent = 0;

      final raf = await file.open(mode: FileMode.read);
      try {
        while (sent < size) {
          if (_socket != ws) throw 'Connection lost during transfer';

          final toRead = (size - sent) < kChunkSize ? (size - sent) : kChunkSize;
          final chunk = await raf.read(toRead);
          if (chunk.isEmpty) break;

          ws.add(chunk);
          sent += chunk.length;

          while (sent - _acked > kWindow) {
            _creditWaiter = Completer<void>();
            await _creditWaiter!.future.timeout(const Duration(seconds: 20));
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

      _resultWaiter = Completer<bool>();
      ws.add(jsonEncode({'t': 'done', 'id': id}));

      final ok = await _resultWaiter!.future
          .timeout(const Duration(seconds: 30), onTimeout: () => false);

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
      _log('Send error: $e');
      if (_socket == ws) ws.add(jsonEncode({'t': 'cancel', 'id': id}));
      _eventController.add(TransferCompletedEvent(
        id: id,
        name: name,
        size: size,
        isSending: true,
        success: false,
        error: e.toString(),
      ));
    } finally {
      _sending = false;
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
      _acceptWaiter = Completer<bool>();
      ws.add(jsonEncode({
        't': 'offer',
        'id': id,
        'name': 'benchmark.bin',
        'size': totalBytes,
        'benchmark': true,
      }));

      final accepted = await _acceptWaiter!.future
          .timeout(const Duration(seconds: 10), onTimeout: () => false);

      if (!accepted) {
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
    final ws = _socket;
    if (ws != null) {
      ws.add(jsonEncode({'t': 'cancel', 'id': transferId}));
    }
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
    _db.close();
  }
}
