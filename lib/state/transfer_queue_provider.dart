import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/engine/engine_api.dart';
import '../core/storage/storage_helper.dart';
import 'engine_provider.dart';

enum QueueItemStatus { queued, transferring, completed, failed, cancelled }

class TransferQueueItem {
  final String id;
  final String name;
  final String? localPath;
  final int size;
  final bool isSending;
  final QueueItemStatus status;
  final double progress;
  final double speedBytesPerSec;
  final String? error;

  const TransferQueueItem({
    required this.id,
    required this.name,
    this.localPath,
    required this.size,
    required this.isSending,
    this.status = QueueItemStatus.queued,
    this.progress = 0.0,
    this.speedBytesPerSec = 0.0,
    this.error,
  });

  TransferQueueItem copyWith({
    String? id,
    String? name,
    String? localPath,
    int? size,
    bool? isSending,
    QueueItemStatus? status,
    double? progress,
    double? speedBytesPerSec,
    String? error,
  }) {
    return TransferQueueItem(
      id: id ?? this.id,
      name: name ?? this.name,
      localPath: localPath ?? this.localPath,
      size: size ?? this.size,
      isSending: isSending ?? this.isSending,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      speedBytesPerSec: speedBytesPerSec ?? this.speedBytesPerSec,
      error: error ?? this.error,
    );
  }
}

class BatchQueueState {
  final List<TransferQueueItem> items;
  final bool isActive;

  const BatchQueueState({
    this.items = const [],
    this.isActive = false,
  });

  int get totalFiles => items.length;
  int get completedFiles =>
      items.where((i) => i.status == QueueItemStatus.completed).length;

  int get totalBytes =>
      items.fold<int>(0, (sum, item) => sum + item.size);

  int get bytesTransferred {
    int total = 0;
    for (final item in items) {
      if (item.status == QueueItemStatus.completed) {
        total += item.size;
      } else if (item.status == QueueItemStatus.transferring) {
        total += (item.size * item.progress).toInt();
      }
    }
    return total;
  }

  double get overallProgress {
    if (totalBytes <= 0) return 0.0;
    return (bytesTransferred / totalBytes).clamp(0.0, 1.0);
  }
}

class TransferQueueNotifier extends Notifier<BatchQueueState> {
  @override
  BatchQueueState build() {
    final engine = ref.watch(engineProvider);
    final sub = engine.events.listen((event) {
      if (event is TransferProgressEvent) {
        _onProgress(event);
      } else if (event is TransferCompletedEvent) {
        _onCompleted(event);
      }
    });
    ref.onDispose(sub.cancel);
    return const BatchQueueState();
  }

  /// Called when a batch of outgoing files or directories is selected for sending.
  Future<void> enqueueOutgoingFiles(List<String> paths) async {
    final payloads = await expandPaths(paths);
    final items = <TransferQueueItem>[];
    for (int i = 0; i < payloads.length; i++) {
      final p = payloads[i];
      items.add(TransferQueueItem(
        id: 'out_${DateTime.now().microsecondsSinceEpoch}_$i',
        name: p.relativePath,
        localPath: p.file.path,
        size: p.size,
        isSending: true,
        status: i == 0 ? QueueItemStatus.transferring : QueueItemStatus.queued,
      ));
    }

    state = BatchQueueState(
      items: items,
      isActive: items.isNotEmpty,
    );
  }

  void _onProgress(TransferProgressEvent event) {
    final currentItems = List<TransferQueueItem>.from(state.items);
    final idx = currentItems.indexWhere((i) => i.name == event.name);

    if (idx != -1) {
      currentItems[idx] = currentItems[idx].copyWith(
        id: event.id,
        status: QueueItemStatus.transferring,
        progress: event.progress,
        speedBytesPerSec: event.speedBytesPerSec,
      );
      state = BatchQueueState(items: currentItems, isActive: true);
    } else {
      // Incoming or external transfer not pre-enqueued
      currentItems.add(TransferQueueItem(
        id: event.id,
        name: event.name,
        size: event.totalBytes,
        isSending: event.isSending,
        status: QueueItemStatus.transferring,
        progress: event.progress,
        speedBytesPerSec: event.speedBytesPerSec,
      ));
      state = BatchQueueState(items: currentItems, isActive: true);
    }
  }

  void _onCompleted(TransferCompletedEvent event) {
    final currentItems = List<TransferQueueItem>.from(state.items);
    final idx = currentItems.indexWhere((i) => i.name == event.name || i.id == event.id);

    if (idx != -1) {
      currentItems[idx] = currentItems[idx].copyWith(
        status: event.success ? QueueItemStatus.completed : QueueItemStatus.failed,
        progress: event.success ? 1.0 : currentItems[idx].progress,
        error: event.error,
        localPath: event.filePath ?? currentItems[idx].localPath,
      );
    } else {
      currentItems.add(TransferQueueItem(
        id: event.id,
        name: event.name,
        size: event.size,
        localPath: event.filePath,
        isSending: event.isSending,
        status: event.success ? QueueItemStatus.completed : QueueItemStatus.failed,
        progress: 1.0,
        error: event.error,
      ));
    }

    // Check if all items are done
    final allDone = currentItems.every(
      (i) => i.status == QueueItemStatus.completed ||
          i.status == QueueItemStatus.failed ||
          i.status == QueueItemStatus.cancelled,
    );

    state = BatchQueueState(
      items: currentItems,
      isActive: !allDone,
    );
  }

  void cancelItem(String id) {
    final currentItems = List<TransferQueueItem>.from(state.items);
    final idx = currentItems.indexWhere((i) => i.id == id);
    if (idx != -1) {
      currentItems[idx] = currentItems[idx].copyWith(
        status: QueueItemStatus.cancelled,
        error: 'Cancelled by user',
      );
      final allDone = currentItems.every(
        (i) =>
            i.status == QueueItemStatus.completed ||
            i.status == QueueItemStatus.failed ||
            i.status == QueueItemStatus.cancelled,
      );
      state = BatchQueueState(
        items: currentItems,
        isActive: !allDone,
      );
    }
  }

  void clearQueue() {
    state = const BatchQueueState();
  }
}

final transferQueueProvider =
    NotifierProvider<TransferQueueNotifier, BatchQueueState>(
  TransferQueueNotifier.new,
);
