import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../constants/network_constants.dart';
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

  void send(EngineCommand cmd) {
    if (cmd is StartServerCommand) {
      _startServer(cmd.port);
    } else if (cmd is ConnectCommand) {
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

      final interfaces =
          await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final ni in interfaces) {
        for (final a in ni.addresses) {
          _log('Local address: ${a.address} (${ni.name})');
        }
      }

      _server!.listen((request) async {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          // Optimization: Compression off to eliminate CPU overhead on media files
          final ws = await WebSocketTransformer.upgrade(
            request,
            compression: CompressionOptions.compressionOff,
          );
          _attach(ws, 'PC');
        } else {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        }
      });
    } catch (e) {
      _log('Server error: $e');
    }
  }

  Future<void> _connect(String host, int port) async {
    final cleanHost = host.trim();
    if (cleanHost.isEmpty) {
      _log('Host address cannot be empty');
      return;
    }
    _log('Connecting to ws://$cleanHost:$port ...');
    try {
      // Optimization: Compression off for client connection
      final ws = await WebSocket.connect(
        'ws://$cleanHost:$port',
        compression: CompressionOptions.compressionOff,
      ).timeout(const Duration(seconds: 5));
      _attach(ws, 'phone');
    } catch (e) {
      _log('Connection failed: $e');
    }
  }

  void _attach(WebSocket ws, String peer) {
    _socket?.close();
    ws.pingInterval = const Duration(seconds: 10);
    _socket = ws;
    _eventController.add(PeerStateEvent(isConnected: true, peerName: peer));
    _log('Connected to $peer');

    ws.listen(
      (data) => _onData(data, peer),
      onDone: () {
        _log('Disconnected from $peer');
        if (_socket == ws) {
          _socket = null;
          _eventController.add(const PeerStateEvent(isConnected: false));
          _abortIncoming('connection closed');
        }
      },
      onError: (e) {
        _log('Socket error: $e');
      },
    );
  }

  void _disconnect() {
    _socket?.close();
    _socket = null;
    _server?.close(force: true);
    _server = null;
    _eventController.add(const PeerStateEvent(isConnected: false));
  }

  // ---------------------------------------------------------------------------
  // Protocol Handling
  // ---------------------------------------------------------------------------

  Future<void> _onData(dynamic data, String peer) async {
    try {
      if (data is String) {
        final m = jsonDecode(data) as Map<String, dynamic>;
        switch (m['t']) {
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
    if (_benchmarkIncomingId != null) {
      _benchmarkReceivedBytes += data.length;
      return;
    }

    final inc = _incoming;
    if (inc == null) return;

    inc.sink.add(data);
    inc.received += data.length;

    // Send credit / progress ack
    if (inc.received - inc.lastAck >= kAckEvery) {
      inc.lastAck = inc.received;
      _socket?.add(jsonEncode(
        {'t': 'progress', 'id': inc.id, 'bytes': inc.received},
      ));
    }

    // Throttled UI progress emission (max 10 Hz)
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

      // Stream file with optimized kChunkSize (256 KB)
      final raf = await file.open(mode: FileMode.read);
      try {
        while (sent < size) {
          if (_socket != ws) throw 'Connection lost during transfer';

          final toRead = (size - sent) < kChunkSize ? (size - sent) : kChunkSize;
          final chunk = await raf.read(toRead);
          if (chunk.isEmpty) break;

          ws.add(chunk);
          sent += chunk.length;

          // Flow control: keep in-flight bytes within kWindow (12 MB)
          while (sent - _acked > kWindow) {
            _creditWaiter = Completer<void>();
            await _creditWaiter!.future.timeout(const Duration(seconds: 20));
            if (_socket != ws) throw 'Connection lost waiting for credit';
          }

          // Throttle UI progress emission (max 10 Hz)
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
  // Benchmark Pipeline (Raw Network Speed without Disk I/O)
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

      // Synthetic 256 KB memory buffer
      final buffer = Uint8List(kChunkSize);

      while (sent < totalBytes) {
        if (_socket != ws) throw 'Connection lost';
        ws.add(buffer);
        sent += buffer.length;

        // Flow control
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

  void dispose() {
    _disconnect();
    _eventController.close();
  }
}
