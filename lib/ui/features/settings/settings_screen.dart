import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/diagnostics/app_logger.dart';
import '../../../core/engine/engine_api.dart';
import '../../../core/platform/share_target_service.dart';
import '../../../core/storage/storage_resolver.dart';
import '../../../data/settings/app_settings.dart';
import '../../../state/engine_provider.dart';
import '../../../ui/design_system/design_system.dart';

/// Settings screen for configuring device name, storage routing, and app behavior.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _nameController;
  bool _isEditingName = false;
  bool _sendToEnabled = false;
  bool _contextMenuEnabled = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _nameController = TextEditingController(text: settings.deviceName);
    if (Platform.isWindows) {
      _sendToEnabled = ShareTargetService.instance.isWindowsSendToEnabled();
      ShareTargetService.instance.isWindowsContextMenuEnabled().then((val) {
        if (mounted) setState(() => _contextMenuEnabled = val);
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final engine = ref.watch(engineProvider);

    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(left: 24, right: 24, bottom: 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ───────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 24, bottom: 20),
              child: Text('Settings', style: HsText.display),
            ),

            // ── Device Identity Section ───────────────────────────────────────
            _SectionHeader(title: 'Device Identity'),
            GlassSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Device Name', style: HsText.title.copyWith(fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(
                    'Shown to nearby devices during discovery and file transfer.',
                    style: HsText.caption,
                  ),
                  const SizedBox(height: 12),
                  if (!_isEditingName)
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: HsColors.glassFillStrong,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: HsColors.glassStroke),
                          ),
                          child: Icon(
                            Platform.isWindows
                                ? Icons.laptop_windows_rounded
                                : Icons.phone_android_rounded,
                            size: 20,
                            color: HsColors.glowHot,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                settings.deviceName.isEmpty
                                    ? (Platform.isWindows ? 'Justin-PC' : 'My Phone')
                                    : settings.deviceName,
                                style: HsText.title.copyWith(fontSize: 16),
                              ),
                              Text('Active device name', style: HsText.caption),
                            ],
                          ),
                        ),
                        GlassButton(
                          label: 'Edit',
                          icon: Icons.edit_rounded,
                          height: 38,
                          fontSize: 13,
                          variant: GlassButtonVariant.secondary,
                          onPressed: () {
                            _nameController.text = settings.deviceName.isEmpty
                                ? (Platform.isWindows ? 'Justin-PC' : 'My Phone')
                                : settings.deviceName;
                            setState(() => _isEditingName = true);
                          },
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: GlassTextField(
                            controller: _nameController,
                            hint: Platform.isWindows ? 'Justin-PC' : 'My Phone',
                            prefixIcon: Platform.isWindows
                                ? Icons.laptop_windows_rounded
                                : Icons.phone_android_rounded,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Save',
                          icon: const Icon(Icons.check_circle_rounded, color: HsColors.glowHot, size: 28),
                          onPressed: () {
                            final name = _nameController.text.trim();
                            ref.read(settingsProvider.notifier).update(
                                  (s) => s.copyWith(deviceName: name),
                                );
                            setState(() => _isEditingName = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Device name updated')),
                            );
                          },
                        ),
                        IconButton(
                          tooltip: 'Cancel',
                          icon: const Icon(Icons.cancel_outlined, color: HsColors.textTertiary, size: 26),
                          onPressed: () {
                            setState(() => _isEditingName = false);
                          },
                        ),
                      ],
                    ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Transfer Rules ───────────────────────────────────────────────
            _SectionHeader(title: 'Transfer Rules'),
            GlassSurface(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Auto-Accept Paired Devices', style: HsText.title.copyWith(fontSize: 14)),
                    subtitle: Text('Instantly receive transfers from trusted devices', style: HsText.caption),
                    value: settings.autoAcceptTrusted,
                    onChanged: (val) {
                      ref.read(settingsProvider.notifier).update(
                            (s) => s.copyWith(autoAcceptTrusted: val),
                          );
                    },
                  ),
                  const Divider(height: 1, color: HsColors.glassStroke),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Pause Receiving', style: HsText.title.copyWith(fontSize: 14)),
                    subtitle: Text('Silently reject incoming file offers', style: HsText.caption),
                    value: settings.pauseReceiving,
                    onChanged: (val) {
                      ref.read(settingsProvider.notifier).update(
                            (s) => s.copyWith(pauseReceiving: val),
                          );
                    },
                  ),
                  const Divider(height: 1, color: HsColors.glassStroke),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Auto-Reconnect Link', style: HsText.title.copyWith(fontSize: 14)),
                    subtitle: Text('Re-establish socket connection when hotspot is active', style: HsText.caption),
                    value: settings.autoReconnect,
                    onChanged: (val) {
                      ref.read(settingsProvider.notifier).update(
                            (s) => s.copyWith(autoReconnect: val),
                          );
                      engine.send(SetAutoReconnectCommand(val));
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Storage Section ───────────────────────────────────────────────
            _SectionHeader(title: 'Storage & Destination'),
            GlassSurface(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_special_rounded, color: HsColors.glowHot),
                title: Text('Download Location', style: HsText.title.copyWith(fontSize: 14)),
                subtitle: Text(
                  Platform.isAndroid
                      ? 'Internal Storage > Download > HotShare'
                      : 'Downloads\\HotShare',
                  style: HsText.caption,
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ── Appearance Section ────────────────────────────────────────────
            _SectionHeader(title: 'Appearance'),
            GlassSurface(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Reduce Motion', style: HsText.title.copyWith(fontSize: 14)),
                    subtitle: Text('Disable drifting glow blobs and pulsing radar rings', style: HsText.caption),
                    value: settings.reduceMotion,
                    onChanged: (val) {
                      ref.read(settingsProvider.notifier).update(
                            (s) => s.copyWith(reduceMotion: val),
                          );
                    },
                  ),
                  const Divider(height: 1, color: HsColors.glassStroke),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Reduce Transparency', style: HsText.title.copyWith(fontSize: 14)),
                    subtitle: Text('Render solid opaque glass backgrounds for lower GPU usage', style: HsText.caption),
                    value: settings.reduceTransparency,
                    onChanged: (val) {
                      ref.read(settingsProvider.notifier).update(
                            (s) => s.copyWith(reduceTransparency: val),
                          );
                    },
                  ),
                ],
              ),
            ),

            if (Platform.isWindows) ...[
              const SizedBox(height: 24),
              _SectionHeader(title: 'Windows Explorer & Shortcuts'),
              GlassSurface(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text("Add to 'Send To' Menu", style: HsText.title.copyWith(fontSize: 14)),
                      subtitle: Text("Right-click file > Send to > HotShare", style: HsText.caption),
                      value: _sendToEnabled,
                      onChanged: (val) async {
                        final ok = await ShareTargetService.instance.setWindowsSendToEnabled(val);
                        if (ok && mounted) {
                          setState(() => _sendToEnabled = val);
                        }
                      },
                    ),
                    const Divider(height: 1, color: HsColors.glassStroke),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text("Add to Right-Click Menu", style: HsText.title.copyWith(fontSize: 14)),
                      subtitle: Text("Show 'Send with HotShare' directly in Explorer context menu", style: HsText.caption),
                      value: _contextMenuEnabled,
                      onChanged: (val) async {
                        final ok = await ShareTargetService.instance.setWindowsContextMenuEnabled(val);
                        if (ok && mounted) {
                          setState(() => _contextMenuEnabled = val);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            // ── Advanced Diagnostics ──────────────────────────────────────────
            _SectionHeader(title: 'Advanced & Diagnostics'),
            GlassSurface(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Verify File Checksums', style: HsText.title.copyWith(fontSize: 14)),
                    subtitle: Text('Compute SHA-256 integrity hash for each transferred file', style: HsText.caption),
                    value: settings.verifyIntegrity,
                    onChanged: (val) {
                      ref.read(settingsProvider.notifier).update(
                            (s) => s.copyWith(verifyIntegrity: val),
                          );
                    },
                  ),
                  const Divider(height: 1, color: HsColors.glassStroke),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('100MB Link Benchmark', style: HsText.title.copyWith(fontSize: 14)),
                            Text('Test true TCP throughput over current hotspot link', style: HsText.caption),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      GlassButton(
                        label: 'Run Test',
                        height: 38,
                        fontSize: 13,
                        variant: GlassButtonVariant.secondary,
                        onPressed: () {
                          engine.send(const RunBenchmarkCommand(sizeMb: 100));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Benchmark started. Check logs / speed readout.')),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: HsColors.glassStroke),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Clear Transfer History', style: HsText.title.copyWith(fontSize: 14)),
                            Text('Delete all transfer logs and history records', style: HsText.caption),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      GlassButton(
                        label: 'Clear',
                        height: 38,
                        fontSize: 13,
                        variant: GlassButtonVariant.danger,
                        onPressed: () => _showPurgeConfirmDialog(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: HsColors.glassStroke),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Export Diagnostics', style: HsText.title.copyWith(fontSize: 14)),
                            Text('Save system report and logs as a text file', style: HsText.caption),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      GlassButton(
                        label: 'Export .txt',
                        height: 38,
                        fontSize: 13,
                        variant: GlassButtonVariant.secondary,
                        onPressed: () => _exportDiagnosticsFile(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ── App Info ──────────────────────────────────────────────────────
            Center(
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.asset(
                      'assets/icon/icon_rounded_512.png',
                      width: 52,
                      height: 52,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('HotShare P2P • v1.0.0', style: HsText.caption),
                  const SizedBox(height: 4),
                  Text('Zero-Cloud Local Wi-Fi Direct Transfer', style: HsText.micro),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPurgeConfirmDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: HsColors.bgRaised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: HsColors.glassStroke),
          ),
          title: Text('Clear Transfer History?', style: HsText.title),
          content: Text(
            'This will permanently delete all transfer records from your history. Your downloaded files on disk will not be deleted.',
            style: HsText.body.copyWith(color: HsColors.textSecondary),
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: GlassButton(
                    label: 'Cancel',
                    variant: GlassButtonVariant.ghost,
                    height: 42,
                    fontSize: 14,
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GlassButton(
                    label: 'Clear All',
                    variant: GlassButtonVariant.danger,
                    height: 42,
                    fontSize: 14,
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      final db = ref.read(databaseProvider);
                      final count = await db.clearAllTransfers();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Cleared $count transfer records')),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> _exportDiagnosticsFile(BuildContext context) async {
    final settings = ref.read(settingsProvider);
    final report = await AppLogger.instance.exportDiagnosticsText(
      deviceName: settings.deviceName,
    );

    try {
      final dir = await StorageResolver.resolveDestinationDirectory(
        fileName: 'hotshare_diagnostics.txt',
      );
      final file = File('${dir.path}${Platform.pathSeparator}hotshare_diagnostics.txt');
      await file.writeAsString(report);

      if (Platform.isAndroid) {
        await StorageResolver.scanMedia(file.path);
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              Platform.isAndroid
                  ? 'Diagnostics saved to Download/HotShare/hotshare_diagnostics.txt'
                  : 'Diagnostics saved to Downloads\\HotShare\\hotshare_diagnostics.txt',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export diagnostics: $e')),
        );
      }
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: HsText.micro.copyWith(
          letterSpacing: 1.2,
          fontWeight: FontWeight.bold,
          color: HsColors.textTertiary,
        ),
      ),
    );
  }
}
