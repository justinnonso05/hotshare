import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/engine/engine_api.dart';
import '../core/engine/hotshare_engine.dart';
import '../data/db/app_database.dart';

/// Provider for the singleton AppDatabase.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Stream of all active paired devices from the database.
final pairedDevicesStreamProvider = StreamProvider<List<Device>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchActiveDevices();
});

/// Stream of persistent transfer history from the database.
final transferHistoryStreamProvider = StreamProvider<List<Transfer>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchTransferHistory();
});

/// Provider for the singleton HotShareEngine instance.
final engineProvider = Provider<HotShareEngine>((ref) {
  final db = ref.watch(databaseProvider);
  final engine = HotShareEngine(db: db);
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
  final bool isPaired;
  final bool isAuthenticated;

  const PeerConnectionState({
    this.isConnected = false,
    this.peerName = '',
    this.isPaired = false,
    this.isAuthenticated = false,
  });

  PeerConnectionState copyWith({
    bool? isConnected,
    String? peerName,
    bool? isPaired,
    bool? isAuthenticated,
  }) {
    return PeerConnectionState(
      isConnected: isConnected ?? this.isConnected,
      peerName: peerName ?? this.peerName,
      isPaired: isPaired ?? this.isPaired,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
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
          isPaired: event.isPaired,
          isAuthenticated: event.isAuthenticated,
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

/// Pairing UI state.
class PairingUiState {
  final bool isWindowOpen;
  final String? code;
  final String? qrPayload;
  final DateTime? expiresAt;
  final List<String>? sasWords;
  final String? peerName;
  final String? peerId;
  final String? statusMessage;

  const PairingUiState({
    this.isWindowOpen = false,
    this.code,
    this.qrPayload,
    this.expiresAt,
    this.sasWords,
    this.peerName,
    this.peerId,
    this.statusMessage,
  });

  PairingUiState copyWith({
    bool? isWindowOpen,
    String? code,
    String? qrPayload,
    DateTime? expiresAt,
    List<String>? sasWords,
    String? peerName,
    String? peerId,
    String? statusMessage,
  }) {
    return PairingUiState(
      isWindowOpen: isWindowOpen ?? this.isWindowOpen,
      code: code ?? this.code,
      qrPayload: qrPayload ?? this.qrPayload,
      expiresAt: expiresAt ?? this.expiresAt,
      sasWords: sasWords ?? this.sasWords,
      peerName: peerName ?? this.peerName,
      peerId: peerId ?? this.peerId,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }
}

class PairingUiNotifier extends Notifier<PairingUiState> {
  @override
  PairingUiState build() {
    final engine = ref.watch(engineProvider);
    final sub = engine.events.listen((event) {
      if (event is PairingWindowOpenedEvent) {
        state = state.copyWith(
          isWindowOpen: true,
          code: event.code,
          qrPayload: event.qrPayload,
          expiresAt: event.expiresAt,
          statusMessage: 'Pairing code active',
        );
      } else if (event is PairingVerificationRequiredEvent) {
        state = state.copyWith(
          sasWords: event.sasWords,
          peerName: event.peerName,
          peerId: event.peerId,
          statusMessage: 'Verify that words match on both screens',
        );
      } else if (event is PairingCompletedEvent) {
        state = PairingUiState(
          statusMessage: event.success
              ? 'Successfully paired with ${event.peerName}!'
              : 'Pairing failed: ${event.error}',
        );
      }
    });
    ref.onDispose(sub.cancel);
    return const PairingUiState();
  }

  void reset() {
    state = const PairingUiState();
  }
}

final pairingUiStateProvider =
    NotifierProvider<PairingUiNotifier, PairingUiState>(
  PairingUiNotifier.new,
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
