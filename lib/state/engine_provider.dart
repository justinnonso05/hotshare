import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/engine/engine_api.dart';
import '../core/engine/hotshare_engine.dart';

/// Provider for the singleton HotShareEngine instance.
final engineProvider = Provider<HotShareEngine>((ref) {
  final engine = HotShareEngine();
  ref.onDispose(engine.dispose);
  return engine;
});

/// Stream of all raw events from the engine.
final engineEventsStreamProvider = StreamProvider<EngineEvent>((ref) {
  final engine = ref.watch(engineProvider);
  return engine.events;
});

/// Connection state model.
class PeerConnectionState {
  final bool isConnected;
  final String peerName;

  const PeerConnectionState({
    this.isConnected = false,
    this.peerName = '',
  });

  PeerConnectionState copyWith({bool? isConnected, String? peerName}) {
    return PeerConnectionState(
      isConnected: isConnected ?? this.isConnected,
      peerName: peerName ?? this.peerName,
    );
  }
}

/// Manages connection state.
class PeerConnectionNotifier extends Notifier<PeerConnectionState> {
  @override
  PeerConnectionState build() {
    final engine = ref.watch(engineProvider);
    final sub = engine.events.listen((event) {
      if (event is PeerStateEvent) {
        state = PeerConnectionState(
          isConnected: event.isConnected,
          peerName: event.peerName,
        );
      }
    });
    ref.onDispose(sub.cancel);
    return const PeerConnectionState();
  }
}

final peerConnectionProvider =
    NotifierProvider<PeerConnectionNotifier, PeerConnectionState>(
  PeerConnectionNotifier.new,
);

/// Active transfer state model.
class ActiveTransferState {
  final String id;
  final String name;
  final int bytesDone;
  final int totalBytes;
  final double progress;
  final double speedBytesPerSec;
  final bool isSending;
  final bool isActive;

  const ActiveTransferState({
    this.id = '',
    this.name = '',
    this.bytesDone = 0,
    this.totalBytes = 0,
    this.progress = 0.0,
    this.speedBytesPerSec = 0.0,
    this.isSending = false,
    this.isActive = false,
  });
}

/// Tracks active transfer progress.
class ActiveTransferNotifier extends Notifier<ActiveTransferState> {
  @override
  ActiveTransferState build() {
    final engine = ref.watch(engineProvider);
    final sub = engine.events.listen((event) {
      if (event is TransferProgressEvent) {
        state = ActiveTransferState(
          id: event.id,
          name: event.name,
          bytesDone: event.bytesDone,
          totalBytes: event.totalBytes,
          progress: event.progress,
          speedBytesPerSec: event.speedBytesPerSec,
          isSending: event.isSending,
          isActive: true,
        );
      } else if (event is TransferCompletedEvent) {
        if (state.id == event.id || !event.isSending) {
          state = const ActiveTransferState(isActive: false);
        }
      }
    });
    ref.onDispose(sub.cancel);
    return const ActiveTransferState();
  }
}

final activeTransferProvider =
    NotifierProvider<ActiveTransferNotifier, ActiveTransferState>(
  ActiveTransferNotifier.new,
);

/// Tracks recent completed files.
class CompletedTransferRecord {
  final String id;
  final String name;
  final String? path;
  final int size;
  final bool isSending;
  final bool success;
  final String? error;
  final DateTime timestamp;

  CompletedTransferRecord({
    required this.id,
    required this.name,
    this.path,
    required this.size,
    required this.isSending,
    required this.success,
    this.error,
  }) : timestamp = DateTime.now();
}

class CompletedTransfersNotifier
    extends Notifier<List<CompletedTransferRecord>> {
  @override
  List<CompletedTransferRecord> build() {
    final engine = ref.watch(engineProvider);
    final sub = engine.events.listen((event) {
      if (event is TransferCompletedEvent && event.success && event.filePath != null) {
        state = [
          CompletedTransferRecord(
            id: event.id,
            name: event.name,
            path: event.filePath,
            size: event.size,
            isSending: event.isSending,
            success: event.success,
            error: event.error,
          ),
          ...state,
        ];
      }
    });
    ref.onDispose(sub.cancel);
    return const [];
  }
}

final completedTransfersProvider =
    NotifierProvider<CompletedTransfersNotifier, List<CompletedTransferRecord>>(
  CompletedTransfersNotifier.new,
);

/// Tracks event log lines.
class EngineLogsNotifier extends Notifier<List<String>> {
  @override
  List<String> build() {
    final engine = ref.watch(engineProvider);
    final sub = engine.events.listen((event) {
      if (event is LogEvent) {
        final time = event.timestamp.toIso8601String().substring(11, 19);
        state = ['[$time] ${event.message}', ...state];
      }
    });
    ref.onDispose(sub.cancel);
    return const [];
  }
}

final engineLogsProvider =
    NotifierProvider<EngineLogsNotifier, List<String>>(
  EngineLogsNotifier.new,
);
