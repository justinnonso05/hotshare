import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/engine/engine_api.dart';
import '../../../../core/storage/storage_resolver.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../state/engine_provider.dart';
import '../../../../state/transfer_queue_provider.dart';
import '../../../design_system/design_system.dart';

/// Card showing the full multi-file transfer queue (pending, active, and completed items).
class TransferQueueCard extends ConsumerWidget {
  final BatchQueueState queue;

  const TransferQueueCard({
    super.key,
    required this.queue,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (queue.items.isEmpty) return const SizedBox.shrink();

    // When only a single file is transferred, show a clean single-file card
    // rather than the multi-item batch queue header
    if (queue.items.length == 1) {
      return _buildSingleTransferCard(context, ref, queue.items.first);
    }

    return GlassSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Queue Header ───
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: HsColors.glowMid.withAlpha(40),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: HsColors.glowMid.withAlpha(80)),
                ),
                child: const Icon(
                  Icons.playlist_play_rounded,
                  color: HsColors.glowHot,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Batch Transfer Queue (${queue.totalFiles} files)',
                      style: HsText.title.copyWith(fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${queue.completedFiles} of ${queue.totalFiles} completed • ${formatBytes(queue.bytesTransferred)} of ${formatBytes(queue.totalBytes)}',
                      style: HsText.caption.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
              Text(
                '${(queue.overallProgress * 100).toInt()}%',
                style: HsText.headline.copyWith(
                  fontSize: 16,
                  color: HsColors.glowHot,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (!queue.isActive) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Dismiss',
                  icon: const Icon(Icons.close_rounded, size: 18, color: HsColors.textTertiary),
                  onPressed: () => ref.read(transferQueueProvider.notifier).clearQueue(),
                ),
              ],
            ],
          ),

          const SizedBox(height: 12),

          // ── Overall Batch Progress Bar ───
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: queue.overallProgress.clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: HsColors.glassFillStrong,
              valueColor: const AlwaysStoppedAnimation<Color>(HsColors.accentPrimary),
            ),
          ),

          const SizedBox(height: 14),
          const Divider(height: 1, color: HsColors.glassStroke),
          const SizedBox(height: 8),

          // ── Items List ───
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: queue.items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, idx) {
                final item = queue.items[idx];
                return _buildQueueItem(context, ref, item);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSingleTransferCard(BuildContext context, WidgetRef ref, TransferQueueItem item) {
    final ext = item.name.contains('.') ? item.name.split('.').last : 'file';
    final kind = StorageResolver.classifyFileKind(item.name);
    final isDone = item.status == QueueItemStatus.completed;
    final isTransferring = item.status == QueueItemStatus.transferring;

    return GlassSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FileGlyph(kind: kind, ext: ext, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: HsText.title.copyWith(fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isTransferring
                          ? '${formatBytes((item.size * item.progress).toInt())} of ${formatBytes(item.size)} • ${formatBytes(item.speedBytesPerSec.round())}/s'
                          : (isDone
                              ? '${formatBytes(item.size)} • Completed'
                              : (item.status == QueueItemStatus.failed
                                  ? 'Transfer failed'
                                  : (item.status == QueueItemStatus.cancelled
                                      ? 'Cancelled'
                                      : 'Queued'))),
                      style: HsText.caption.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isTransferring) ...[
                Text(
                  '${(item.progress * 100).toInt()}%',
                  style: HsText.headline.copyWith(
                    fontSize: 15,
                    color: HsColors.glowHot,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Cancel Transfer',
                  icon: const Icon(Icons.cancel_outlined, size: 20, color: HsColors.danger),
                  onPressed: () {
                    ref.read(engineProvider).send(CancelTransferCommand(item.id));
                    ref.read(transferQueueProvider.notifier).cancelItem(item.id);
                  },
                ),
              ] else if (isDone) ...[
                const Icon(Icons.check_circle_rounded, color: HsColors.success, size: 22),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Dismiss',
                  icon: const Icon(Icons.close_rounded, size: 18, color: HsColors.textTertiary),
                  onPressed: () => ref.read(transferQueueProvider.notifier).clearQueue(),
                ),
              ] else ...[
                IconButton(
                  tooltip: 'Dismiss',
                  icon: const Icon(Icons.close_rounded, size: 18, color: HsColors.textTertiary),
                  onPressed: () => ref.read(transferQueueProvider.notifier).clearQueue(),
                ),
              ],
            ],
          ),
          if (isTransferring) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: item.progress.clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: HsColors.glassFillStrong,
                valueColor: const AlwaysStoppedAnimation<Color>(HsColors.accentPrimary),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQueueItem(BuildContext context, WidgetRef ref, TransferQueueItem item) {
    final ext = item.name.contains('.') ? item.name.split('.').last : 'file';
    final kind = StorageResolver.classifyFileKind(item.name);

    Widget statusWidget;
    switch (item.status) {
      case QueueItemStatus.completed:
        statusWidget = const Icon(Icons.check_circle_rounded, color: HsColors.success, size: 18);
        break;
      case QueueItemStatus.failed:
        statusWidget = const Icon(Icons.error_outline_rounded, color: HsColors.danger, size: 18);
        break;
      case QueueItemStatus.cancelled:
        statusWidget = const Icon(Icons.cancel_outlined, color: HsColors.textTertiary, size: 18);
        break;
      case QueueItemStatus.transferring:
        statusWidget = Text(
          '${(item.progress * 100).toInt()}%',
          style: const TextStyle(
            color: HsColors.glowHot,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        );
        break;
      case QueueItemStatus.queued:
        statusWidget = Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: HsColors.glassFillStrong,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'Queued',
            style: HsText.micro.copyWith(color: HsColors.textTertiary),
          ),
        );
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: item.status == QueueItemStatus.transferring
            ? HsColors.glowMid.withAlpha(20)
            : HsColors.glassFillStrong.withAlpha(40),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: item.status == QueueItemStatus.transferring
              ? HsColors.glowHot.withAlpha(80)
              : HsColors.glassStroke.withAlpha(50),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              FileGlyph(kind: kind, ext: ext, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: HsText.body.copyWith(
                        fontSize: 12,
                        fontWeight: item.status == QueueItemStatus.transferring
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      item.status == QueueItemStatus.transferring
                          ? '${formatBytes((item.size * item.progress).toInt())} of ${formatBytes(item.size)} • ${formatBytes(item.speedBytesPerSec.round())}/s'
                          : formatBytes(item.size),
                      style: HsText.caption.copyWith(fontSize: 10),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              statusWidget,
              if (item.status == QueueItemStatus.transferring || item.status == QueueItemStatus.queued) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: () {
                    ref.read(engineProvider).send(CancelTransferCommand(item.id));
                    ref.read(transferQueueProvider.notifier).cancelItem(item.id);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.cancel_outlined, size: 18, color: HsColors.danger),
                  ),
                ),
              ],
            ],
          ),
          if (item.status == QueueItemStatus.transferring) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: item.progress.clamp(0.0, 1.0),
                minHeight: 2.5,
                backgroundColor: HsColors.glassFillStrong,
                valueColor: const AlwaysStoppedAnimation<Color>(HsColors.accentPrimary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
