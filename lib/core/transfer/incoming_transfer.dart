import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

/// Sink to capture the resulting [crypto.Digest] from chunked hash conversion.
class DigestSink implements Sink<crypto.Digest> {
  crypto.Digest? value;

  @override
  void add(crypto.Digest data) => value = data;

  @override
  void close() {}
}

/// Holds the in-progress stream state of a file currently being received,
/// including partial resumption offset and running SHA-256 checksum computation.
class IncomingTransfer {
  IncomingTransfer({
    required this.id,
    required this.name,
    required this.size,
    required this.file,
    required this.sink,
    this.offset = 0,
    bool enableChecksum = true,
  })  : received = offset,
        lastAck = offset {
    if (enableChecksum && offset == 0) {
      _digestSink = DigestSink();
      _hasher = crypto.sha256.startChunkedConversion(_digestSink!);
    }
  }

  final String id;
  final String name;
  final int size;
  final File file;
  final IOSink sink;
  final int offset;

  int received;
  int lastAck;

  DigestSink? _digestSink;
  ByteConversionSink? _hasher;

  void addChunk(List<int> chunk) {
    sink.add(chunk);
    received += chunk.length;
    _hasher?.add(chunk);
  }

  String? finalizeChecksum() {
    if (_hasher != null && _digestSink != null) {
      _hasher?.close();
      return _digestSink?.value?.toString();
    }
    return null;
  }
}
