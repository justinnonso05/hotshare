import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

const int kPort = 8080;
const int kWindow = 4 * 1024 * 1024; // max bytes in flight before the sender waits
const int kAckEvery = 1024 * 1024; // receiver reports progress every 1 MB

void main() => runApp(const HotspotShareApp());

class HotspotShareApp extends StatelessWidget {
  const HotspotShareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hotspot Share',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const SharePage(),
    );
  }
}

/// State of a file we are currently receiving.
class _Incoming {
  _Incoming(this.id, this.name, this.size, this.file, this.sink);
  final String id;
  final String name;
  final int size;
  final File file;
  final IOSink sink;
  int received = 0;
  int lastAck = 0;
}

class SharePage extends StatefulWidget {
  const SharePage({super.key});

  @override
  State<SharePage> createState() => _SharePageState();
}

class _SharePageState extends State<SharePage> {
  final List<String> _log = [];
  final List<File> _received = [];
  final _ipController = TextEditingController();
  final _msgController = TextEditingController(text: 'Hello from here');

  HttpServer? _server;
  WebSocket? _socket;

  // Receiving state
  _Incoming? _incoming;
  double? _recvProgress; // null = idle
  String _recvName = '';

  // Sending state
  bool _sending = false;
  double? _sendProgress; // null = idle
  String _sendName = '';
  int _sendSize = 0;
  int _acked = 0;
  Completer<bool>? _acceptWaiter;
  Completer<void>? _creditWaiter;
  Completer<bool>? _resultWaiter;

  bool _dragging = false;

  // Android = server (the phone). Anything else = client (the PC).
  bool get _isPhone => Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    if (_isPhone) {
      _startServer();
    } else {
      _findGateway();
    }
  }

  @override
  void dispose() {
    _socket?.close();
    _server?.close(force: true);
    _ipController.dispose();
    _msgController.dispose();
    super.dispose();
  }

  void _addLog(String line) {
    if (!mounted) return;
    final time = DateTime.now().toIso8601String().substring(11, 19);
    setState(() => _log.insert(0, '[$time] $line'));
  }

  // ---------------------------------------------------------------------------
  // Connection (same as the connection test)
  // ---------------------------------------------------------------------------

  Future<void> _startServer() async {
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, kPort);
      _addLog('Server listening on port $kPort');

      final interfaces =
          await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final ni in interfaces) {
        for (final a in ni.addresses) {
          _addLog('Phone address: ${a.address} (${ni.name})');
        }
      }

      _server!.listen((request) async {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          final ws = await WebSocketTransformer.upgrade(request);
          _attach(ws, 'PC');
        } else {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        }
      });
    } catch (e) {
      _addLog('Server failed: $e');
    }
  }

  Future<void> _findGateway() async {
    try {
      final result = await Process.run('route', ['print', '-4']);
      final gateways = RegExp(
              r'0\.0\.0\.0\s+0\.0\.0\.0\s+(\d+\.\d+\.\d+\.\d+)')
          .allMatches(result.stdout.toString())
          .map((m) => m.group(1)!)
          .toList();
      _addLog(
          'Gateways found: ${gateways.isEmpty ? 'none' : gateways.join(', ')}');
      if (gateways.isNotEmpty) _ipController.text = gateways.first;
    } catch (e) {
      _addLog('Gateway lookup failed: $e');
    }
  }

  Future<void> _connect() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) {
      _addLog('Enter the phone IP first');
      return;
    }
    _addLog('Connecting to ws://$ip:$kPort ...');
    try {
      final ws = await WebSocket.connect('ws://$ip:$kPort')
          .timeout(const Duration(seconds: 5));
      _attach(ws, 'phone');
    } catch (e) {
      _addLog('Connect failed: $e');
    }
  }

  void _attach(WebSocket ws, String peer) {
    if (!mounted) return;
    _socket?.close();
    ws.pingInterval = const Duration(seconds: 10);
    setState(() => _socket = ws);
    _addLog('Connected to $peer');

    ws.listen(
      (data) => _onData(data, peer),
      onDone: () {
        _addLog('Disconnected from $peer');
        if (_socket == ws) {
          _abortIncoming('connection closed');
          if (mounted) setState(() => _socket = null);
        }
      },
      onError: (e) => _addLog('Error: $e'),
    );
  }

  // ---------------------------------------------------------------------------
  // Protocol
  //
  // Text frames  = JSON control messages:
  //   text      {t, body}
  //   offer     {t, id, name, size}      sender -> receiver
  //   accept    {t, id}                  receiver -> sender (or reject)
  //   progress  {t, id, bytes}           receiver -> sender, every ~1 MB
  //   done      {t, id}                  sender -> receiver, after last chunk
  //   result    {t, id, ok}              receiver -> sender, size verified
  //   cancel    {t, id}                  sender -> receiver
  // Binary frames = raw file chunks for the transfer that was accepted.
  // ---------------------------------------------------------------------------

  Future<void> _onData(dynamic data, String peer) async {
    try {
      if (data is String) {
        final m = jsonDecode(data) as Map<String, dynamic>;
        switch (m['t']) {
          case 'text':
            _addLog('$peer says: ${m['body']}');
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
      _addLog('Protocol error: $e');
    }
  }

  void _completeAccept(bool v) {
    final w = _acceptWaiter;
    if (w != null && !w.isCompleted) w.complete(v);
  }

  // ---------- receiving ----------

  Future<void> _onOffer(Map<String, dynamic> m) async {
    final ws = _socket;
    if (ws == null) return;
    if (_incoming != null) {
      ws.add(jsonEncode({'t': 'reject', 'id': m['id']}));
      return;
    }
    final name = _safeName(m['name'] as String);
    final size = (m['size'] as num).toInt();
    final dir = await _saveDir();
    final file = _uniqueFile(dir, name);
    final inc =
        _Incoming(m['id'] as String, name, size, file, file.openWrite());
    _incoming = inc;
    setState(() {
      _recvName = name;
      _recvProgress = 0;
    });
    _addLog('Receiving $name (${_fmt(size)})');
    // Test build: auto-accept. Later this becomes an accept/reject prompt.
    ws.add(jsonEncode({'t': 'accept', 'id': inc.id}));
  }

  void _onChunk(List<int> data) {
    final inc = _incoming;
    if (inc == null) return;
    inc.sink.add(data);
    inc.received += data.length;
    if (inc.received - inc.lastAck >= kAckEvery) {
      inc.lastAck = inc.received;
      _socket?.add(jsonEncode(
          {'t': 'progress', 'id': inc.id, 'bytes': inc.received}));
      setState(() =>
          _recvProgress = inc.size == 0 ? 1 : inc.received / inc.size);
    }
  }

  Future<void> _onDone(Map<String, dynamic> m) async {
    final inc = _incoming;
    if (inc == null) return;
    _incoming = null;
    var ok = false;
    try {
      await inc.sink.flush();
      await inc.sink.close();
      ok = inc.received == inc.size;
    } catch (e) {
      _addLog('Write error: $e');
    }
    _socket?.add(jsonEncode({'t': 'result', 'id': inc.id, 'ok': ok}));
    if (!mounted) return;
    setState(() {
      _recvProgress = null;
      if (ok) _received.insert(0, inc.file);
    });
    _addLog(ok
        ? 'Saved ${inc.name} (${_fmt(inc.size)})'
        : 'Size mismatch for ${inc.name}: got ${inc.received} of ${inc.size}');
  }

  Future<void> _abortIncoming(String why) async {
    final inc = _incoming;
    if (inc == null) return;
    _incoming = null;
    try {
      await inc.sink.close();
      if (await inc.file.exists()) await inc.file.delete();
    } catch (_) {}
    if (mounted) setState(() => _recvProgress = null);
    _addLog('Receive aborted: $why');
  }

  Future<Directory> _saveDir() async {
    final Directory base;
    if (Platform.isAndroid) {
      // App-specific storage: no permission needed. Moving to the public
      // Downloads folder (MediaStore) comes in a later step.
      base = (await getExternalStorageDirectory()) ??
          await getApplicationDocumentsDirectory();
    } else {
      base = (await getDownloadsDirectory()) ??
          await getApplicationDocumentsDirectory();
    }
    final dir = Directory('${base.path}${Platform.pathSeparator}HotShare');
    await dir.create(recursive: true);
    return dir;
  }

  /// Strips any path the sender included and characters Windows rejects.
  String _safeName(String name) {
    final last = name.split(RegExp(r'[\\/]')).last;
    final clean = last.replaceAll(RegExp(r'[<>:"|?*\x00-\x1f]'), '_').trim();
    return clean.isEmpty ? 'file' : clean;
  }

  File _uniqueFile(Directory dir, String name) {
    final sep = Platform.pathSeparator;
    var f = File('${dir.path}$sep$name');
    if (!f.existsSync()) return f;
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var i = 1;
    while (f.existsSync()) {
      f = File('${dir.path}$sep$base ($i)$ext');
      i++;
    }
    return f;
  }

  // ---------- sending ----------

  void _onProgress(Map<String, dynamic> m) {
    _acked = (m['bytes'] as num).toInt();
    final w = _creditWaiter;
    if (w != null && !w.isCompleted) w.complete();
    if (_sending && mounted) {
      setState(() => _sendProgress =
          _sendSize == 0 ? 1 : (_acked / _sendSize).clamp(0.0, 1.0));
    }
  }

  void _onResult(Map<String, dynamic> m) {
    final w = _resultWaiter;
    if (w != null && !w.isCompleted) w.complete(m['ok'] == true);
  }

  Future<void> _pickAndSend() async {
    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return;
    for (final f in files) {
      final path = f.path;
      if (path != null) await _sendFile(path);
    }
  }

  Future<void> _sendFile(String path) async {
    final ws = _socket;
    if (ws == null) {
      _addLog('Not connected');
      return;
    }
    if (_sending) {
      _addLog('Another transfer is in progress');
      return;
    }
    final file = File(path);
    if (!await file.exists()) {
      _addLog('File not found: $path');
      return;
    }
    final size = await file.length();
    final name = path.split(RegExp(r'[\\/]')).last;
    final id = DateTime.now().microsecondsSinceEpoch.toString();

    _sending = true;
    _acked = 0;
    setState(() {
      _sendName = name;
      _sendSize = size;
      _sendProgress = 0;
    });
    _addLog('Offering $name (${_fmt(size)})');

    try {
      _acceptWaiter = Completer<bool>();
      ws.add(jsonEncode({'t': 'offer', 'id': id, 'name': name, 'size': size}));
      final accepted = await _acceptWaiter!.future
          .timeout(const Duration(seconds: 15), onTimeout: () => false);
      if (!accepted) {
        _addLog('Receiver did not accept $name');
        return;
      }

      var sent = 0;
      await for (final chunk in file.openRead()) {
        if (_socket != ws) throw 'connection lost';
        ws.add(chunk);
        sent += chunk.length;
        // Flow control: never get more than kWindow bytes ahead of the receiver.
        while (sent - _acked > kWindow) {
          _creditWaiter = Completer<void>();
          await _creditWaiter!.future.timeout(const Duration(seconds: 20));
          if (_socket != ws) throw 'connection lost';
        }
      }

      _resultWaiter = Completer<bool>();
      ws.add(jsonEncode({'t': 'done', 'id': id}));
      final ok = await _resultWaiter!.future
          .timeout(const Duration(seconds: 30), onTimeout: () => false);
      _addLog(ok
          ? 'Delivered $name, size verified'
          : 'Transfer of $name failed verification');
    } catch (e) {
      _addLog('Send failed: $e');
      if (_socket == ws) ws.add(jsonEncode({'t': 'cancel', 'id': id}));
    } finally {
      _sending = false;
      if (mounted) setState(() => _sendProgress = null);
    }
  }

  void _sendText() {
    final ws = _socket;
    if (ws == null) {
      _addLog('Not connected');
      return;
    }
    ws.add(jsonEncode({'t': 'text', 'body': _msgController.text}));
    _addLog('You: ${_msgController.text}');
  }

  String _fmt(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  Widget _dropZone(bool connected) {
    final zone = InkWell(
      onTap: connected ? _pickAndSend : null,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 110,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _dragging ? Colors.indigo : Colors.grey,
            width: _dragging ? 3 : 1.5,
          ),
          color: _dragging ? Colors.indigo.withValues(alpha: 0.08) : null,
        ),
        child: Text(
          connected
              ? (_isPhone
                  ? 'Tap to choose files to send'
                  : 'Drop files here, or click to choose')
              : 'Connect first',
        ),
      ),
    );
    if (_isPhone) return zone;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (d) async {
        setState(() => _dragging = false);
        for (final f in d.files) {
          await _sendFile(f.path);
        }
      },
      child: zone,
    );
  }

  @override
  Widget build(BuildContext context) {
    final connected = _socket != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isPhone ? 'Phone (server)' : 'PC (client)'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(Icons.circle,
                  size: 14, color: connected ? Colors.green : Colors.red),
              const SizedBox(width: 8),
              Text(connected ? 'Connected' : 'Not connected'),
            ]),
            const SizedBox(height: 12),
            if (!_isPhone) ...[
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _ipController,
                    decoration: const InputDecoration(
                        labelText: 'Phone IP', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _connect, child: const Text('Connect')),
              ]),
              const SizedBox(height: 12),
            ],
            _dropZone(connected),
            const SizedBox(height: 12),
            if (_sendProgress != null) ...[
              Text('Sending $_sendName (${_fmt(_sendSize)})'),
              const SizedBox(height: 4),
              LinearProgressIndicator(value: _sendProgress),
              const SizedBox(height: 8),
            ],
            if (_recvProgress != null) ...[
              Text('Receiving $_recvName'),
              const SizedBox(height: 4),
              LinearProgressIndicator(value: _recvProgress),
              const SizedBox(height: 8),
            ],
            for (final f in _received.take(3))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: Text(f.path.split(RegExp(r'[\\/]')).last,
                    overflow: TextOverflow.ellipsis),
                subtitle: Text(f.path, overflow: TextOverflow.ellipsis),
                onTap: () => OpenFilex.open(f.path),
              ),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _msgController,
                  decoration: const InputDecoration(
                      labelText: 'Message', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                  onPressed: connected ? _sendText : null,
                  child: const Text('Send')),
            ]),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: _log.length,
                itemBuilder: (_, i) => Text(
                  _log[i],
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}