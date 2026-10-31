import 'dart:io';

/// Holds the in-progress stream state of a file currently being received.
class IncomingTransfer {
  IncomingTransfer({
    required this.id,
    required this.name,
    required this.size,
    required this.file,
    required this.sink,
  });

  final String id;
  final String name;
  final int size;
  final File file;
  final IOSink sink;

  int received = 0;
  int lastAck = 0;
}
