import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/storage_resolver.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/db/app_database.dart';
import '../../../state/engine_provider.dart';
import '../../../ui/design_system/design_system.dart';

/// Displays full transfer history with section grouping and filter chips.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  String _filter = 'all'; // all | sent | received | images | videos | documents | failed
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  static const _filters = [
    ('all', 'All'),
    ('sent', 'Sent'),
    ('received', 'Received'),
    ('image', 'Images'),
    ('video', 'Videos'),
    ('document', 'Docs'),
    ('failed', 'Failed'),
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Transfer> _applyFilters(List<Transfer> all) {
    var list = all;

    // Text search
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((t) => t.name.toLowerCase().contains(q)).toList();
    }

    switch (_filter) {
      case 'sent':
        list = list.where((t) => t.direction == 'out').toList();
      case 'received':
        list = list.where((t) => t.direction == 'in').toList();
      case 'image':
      case 'video':
      case 'document':
        list = list.where((t) => t.kind == _filter).toList();
      case 'failed':
        list = list.where((t) => t.status == 'failed').toList();
    }
    return list;
  }

  Map<String, List<Transfer>> _groupByDate(List<Transfer> items) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final Map<String, List<Transfer>> groups = {};
    for (final t in items) {
      final d = DateTime(t.startedAt.year, t.startedAt.month, t.startedAt.day);
      String label;
      if (d == today) {
        label = 'Today';
      } else if (d == yesterday) {
        label = 'Yesterday';
      } else {
        label =
            '${d.day} ${_monthName(d.month)} ${d.year}';
      }
      groups.putIfAbsent(label, () => []).add(t);
    }
    return groups;
  }

  String _monthName(int m) => const [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m];

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(transferHistoryStreamProvider);

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ─────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Text('History', style: HsText.display),
          ),

          // ── Search ─────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: GlassTextField(
              controller: _searchCtrl,
              hint: 'Search files…',
              prefixIcon: Icons.search_rounded,
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),

          const SizedBox(height: 12),

          // ── Filter chips ───────────────────────────────────────────────────
          SizedBox(
            height: 36,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              scrollDirection: Axis.horizontal,
              itemCount: _filters.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final (key, label) = _filters[i];
                final selected = _filter == key;
                return FilterChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: (_) => setState(() => _filter = key),
                  backgroundColor: HsColors.glassFillStrong,
                  selectedColor: HsColors.glowMid.withAlpha(60),
                  labelStyle: HsText.caption.copyWith(
                    color: selected
                        ? HsColors.textPrimary
                        : HsColors.textTertiary,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                  side: BorderSide(
                    color: selected
                        ? HsColors.glowMid.withAlpha(120)
                        : HsColors.glassStroke,
                    width: 0.5,
                  ),
                  shape: const StadiumBorder(),
                  showCheckmark: false,
                );
              },
            ),
          ),

          const SizedBox(height: 8),

          // ── List ───────────────────────────────────────────────────────────
          Expanded(
            child: historyAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(
                  color: HsColors.accentPrimary,
                  strokeWidth: 2,
                ),
              ),
              error: (e, _) => Center(
                child: Text('Error: $e', style: HsText.caption),
              ),
              data: (allItems) {
                final items = _applyFilters(allItems);
                if (items.isEmpty) {
                  return _EmptyState(filtered: _filter != 'all' || _searchQuery.isNotEmpty);
                }
                final groups = _groupByDate(items);
                final sectionKeys = groups.keys.toList();

                return ListView.builder(
                  padding: const EdgeInsets.only(
                      left: 24, right: 24, bottom: 120),
                  itemCount: sectionKeys.length,
                  itemBuilder: (_, sectionIdx) {
                    final label = sectionKeys[sectionIdx];
                    final rows = groups[label]!;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 20),
                        Text(label,
                            style: HsText.caption.copyWith(
                              fontWeight: FontWeight.w600,
                              color: HsColors.textTertiary,
                            )),
                        const SizedBox(height: 8),
                        GlassSurface(
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              for (int i = 0; i < rows.length; i++) ...[
                                if (i > 0)
                                  const Divider(
                                    height: 1,
                                    color: HsColors.glassStroke,
                                    indent: 64,
                                  ),
                                _TransferRow(transfer: rows[i]),
                              ],
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TransferRow extends StatelessWidget {
  final Transfer transfer;

  const _TransferRow({required this.transfer});

  String get _ext {
    final dot = transfer.name.lastIndexOf('.');
    if (dot < 0 || dot == transfer.name.length - 1) return '?';
    return transfer.name.substring(dot + 1);
  }

  @override
  Widget build(BuildContext context) {
    final time =
        '${transfer.startedAt.hour.toString().padLeft(2, '0')}:${transfer.startedAt.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // File glyph
          FileGlyph(kind: transfer.kind, ext: _ext, size: 42),
          const SizedBox(width: 14),

          // Name / meta
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transfer.name,
                  style: HsText.body.copyWith(
                    color: HsColors.textPrimary,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  '${formatBytes(transfer.size)}  •  $time',
                  style: HsText.caption,
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Direction icon
          Icon(
            transfer.direction == 'out'
                ? Icons.upload_rounded
                : Icons.download_rounded,
            size: 16,
            color: transfer.direction == 'out'
                ? HsColors.glowHot
                : HsColors.success,
          ),

          const SizedBox(width: 8),

          // Status chip
          _StatusChip(status: transfer.status),

          // Open / show button (if saved locally)
          if (transfer.localPath != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () =>
                  StorageResolver.showInFileManager(transfer.localPath!),
              child: const Icon(Icons.folder_open_rounded,
                  size: 18, color: HsColors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status) {
      case 'done':
        color = HsColors.success;
        label = 'Done';
      case 'failed':
        color = HsColors.danger;
        label = 'Failed';
      case 'transferring':
        color = HsColors.warning;
        label = 'Active';
      case 'cancelled':
        color = HsColors.textTertiary;
        label = 'Cancelled';
      default:
        color = HsColors.textTertiary;
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(HsColors.radiusPill),
        border: Border.all(color: color.withAlpha(80), width: 0.5),
      ),
      child: Text(label,
          style: HsText.micro.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          )),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool filtered;
  const _EmptyState({required this.filtered});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.history_rounded,
                size: 56, color: HsColors.textTertiary),
            const SizedBox(height: 16),
            Text(
              filtered
                  ? 'No matching transfers'
                  : 'Nothing sent yet.\nDrop a file on a device to start.',
              style: HsText.body,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
