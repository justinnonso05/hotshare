import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/engine/engine_api.dart';
import '../../../core/storage/storage_resolver.dart';
import '../../../core/utils/formatters.dart';
import '../../../state/engine_provider.dart';
import '../../../ui/design_system/design_system.dart';

/// Translucent Quick-Send Sheet presented when files are shared via Android Share Sheet
/// or Windows CLI/Explorer integration.
class QuickSendSheet extends ConsumerWidget {
  final List<String> filePaths;
  final VoidCallback onDismiss;

  const QuickSendSheet({
    super.key,
    required this.filePaths,
    required this.onDismiss,
  });

  static void show(BuildContext context, List<String> paths) {
    if (paths.isEmpty) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => QuickSendSheet(
        filePaths: paths,
        onDismiss: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(peerConnectionProvider);
    final totalBytes = _calculateTotalBytes(filePaths);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 16,
        right: 16,
      ),
      child: GlassSurface(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: HsColors.glassStroke,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Quick Send', style: HsText.headline),
                Text(
                  '${filePaths.length} file${filePaths.length == 1 ? '' : 's'} (${formatBytes(totalBytes)})',
                  style: HsText.caption.copyWith(color: HsColors.glowHot),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // File items strip
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: filePaths.length,
                separatorBuilder: (context, index) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final path = filePaths[i];
                  final name = path.split(Platform.pathSeparator).last;
                  final kind = StorageResolver.classifyFileKind(name);
                  final ext = name.contains('.') ? name.split('.').last : '';

                  return Container(
                    width: 180,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: HsColors.glassFillStrong,
                      borderRadius: BorderRadius.circular(HsColors.radiusSmall),
                      border: Border.all(color: HsColors.glassStroke, width: 0.5),
                    ),
                    child: Row(
                      children: [
                        FileGlyph(kind: kind, ext: ext, size: 36),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: HsText.body.copyWith(fontSize: 12, color: HsColors.textPrimary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                _getFileSize(path),
                                style: HsText.micro,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 20),

            // Connection target status
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: conn.isConnected
                    ? HsColors.success.withAlpha(25)
                    : HsColors.warning.withAlpha(25),
                borderRadius: BorderRadius.circular(HsColors.radiusSmall),
                border: Border.all(
                  color: conn.isConnected
                      ? HsColors.success.withAlpha(80)
                      : HsColors.warning.withAlpha(80),
                  width: 0.5,
                ),
              ),
              child: Row(
                children: [
                  StatusDot(
                    state: conn.isConnected
                        ? StatusDotState.online
                        : StatusDotState.reconnecting,
                    size: 8,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      conn.isConnected
                          ? 'Ready to transfer to ${conn.peerName}'
                          : 'No device connected. Files will be queued until a device connects.',
                      style: HsText.caption.copyWith(color: HsColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Actions
            Row(
              children: [
                Expanded(
                  child: GlassButton(
                    label: 'Cancel',
                    variant: GlassButtonVariant.ghost,
                    onPressed: onDismiss,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GlassButton(
                    label: conn.isConnected ? 'Send Now' : 'Queue & Send',
                    icon: Icons.send_rounded,
                    onPressed: () {
                      ref.read(engineProvider).send(SendFilesCommand(filePaths));
                      onDismiss();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  int _calculateTotalBytes(List<String> paths) {
    int total = 0;
    for (final p in paths) {
      try {
        final f = File(p);
        if (f.existsSync()) total += f.lengthSync();
      } catch (_) {}
    }
    return total;
  }

  String _getFileSize(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) return formatBytes(f.lengthSync());
    } catch (_) {}
    return '';
  }
}
