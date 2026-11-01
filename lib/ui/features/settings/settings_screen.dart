import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/diagnostics/app_logger.dart';
import '../../../core/engine/engine_api.dart';
import '../../../core/platform/share_target_service.dart';
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
                      const SizedBox(width: 12),
                      GlassButton(
                        label: 'Save',
                        height: 48,
                        fontSize: 13,
                        onPressed: () {
                          final name = _nameController.text.trim();
                          ref.read(settingsProvider.notifier).update(
                                (s) => s.copyWith(deviceName: name),
                              );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Device name updated')),
                          );
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
            _SectionHeader(title: 'Storage & Organization'),
            GlassSurface(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                children: [
                  if (Platform.isAndroid) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Storage Destination', style: HsText.title.copyWith(fontSize: 14)),
                      subtitle: Text(
                        settings.androidSaveMode == 'byType'
                            ? 'Organized by type into Pictures, Movies, Music, Downloads'
                            : 'All files placed directly in Downloads/HotShare',
                        style: HsText.caption,
                      ),
                      trailing: DropdownButton<String>(
                        value: settings.androidSaveMode,
                        dropdownColor: HsColors.bgRaised,
                        style: const TextStyle(color: HsColors.textPrimary, fontSize: 13),
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: 'byType', child: Text('By File Type')),
                          DropdownMenuItem(value: 'downloads', child: Text('Downloads')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            ref.read(settingsProvider.notifier).update(
                                  (s) => s.copyWith(androidSaveMode: val),
                                );
                          }
                        },
                      ),
                    ),
                    const Divider(height: 1, color: HsColors.glassStroke),
                  ],
                  if (Platform.isWindows) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Destination Folder', style: HsText.title.copyWith(fontSize: 14)),
                      subtitle: Text(
                        settings.saveRootWindows ?? 'Default: ~/Downloads/HotShare',
                        style: HsText.caption,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.folder_open_rounded, color: HsColors.glowHot),
                        onPressed: () async {
                          final dir = await FilePicker.getDirectoryPath();
                          if (dir != null) {
                            ref.read(settingsProvider.notifier).update(
                                  (s) => s.copyWith(saveRootWindows: dir),
                                );
                          }
                        },
                      ),
                    ),
                    const Divider(height: 1, color: HsColors.glassStroke),
                  ],
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Subfolder Grouping', style: HsText.title.copyWith(fontSize: 14)),
                    subtitle: Text('Group incoming transfers into date or type subfolders', style: HsText.caption),
                    trailing: DropdownButton<String>(
                      value: settings.organiseBy,
                      dropdownColor: HsColors.bgRaised,
                      style: const TextStyle(color: HsColors.textPrimary, fontSize: 13),
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(value: 'none', child: Text('Flat')),
                        DropdownMenuItem(value: 'type', child: Text('By Type')),
                        DropdownMenuItem(value: 'date', child: Text('By Month')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          ref.read(settingsProvider.notifier).update(
                                (s) => s.copyWith(organiseBy: val),
                              );
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Appearance Section ────────────────────────────────────────────
            _SectionHeader(title: 'Appearance'),
            GlassSurface(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Theme', style: HsText.title.copyWith(fontSize: 14)),
                    trailing: DropdownButton<String>(
                      value: settings.theme,
                      dropdownColor: HsColors.bgRaised,
                      style: const TextStyle(color: HsColors.textPrimary, fontSize: 13),
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(value: 'dark', child: Text('Dark Ember')),
                        DropdownMenuItem(value: 'light', child: Text('Light')),
                        DropdownMenuItem(value: 'system', child: Text('System')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          ref.read(settingsProvider.notifier).update(
                                (s) => s.copyWith(theme: val),
                              );
                        }
                      },
                    ),
                  ),
                  const Divider(height: 1, color: HsColors.glassStroke),
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('100MB Link Benchmark', style: HsText.title.copyWith(fontSize: 14)),
                          Text('Test true TCP throughput over current hotspot link', style: HsText.caption),
                        ],
                      ),
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Purge Transfer History', style: HsText.title.copyWith(fontSize: 14)),
                          Text('Clear all transfer records older than 30 days', style: HsText.caption),
                        ],
                      ),
                      GlassButton(
                        label: 'Purge',
                        height: 38,
                        fontSize: 13,
                        variant: GlassButtonVariant.ghost,
                        onPressed: () async {
                          final db = ref.read(databaseProvider);
                          final count = await db.purgeOldTransfers(DateTime.now().subtract(const Duration(days: 30)));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Purged $count old records')),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: HsColors.glassStroke),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Diagnostics & Logs', style: HsText.title.copyWith(fontSize: 14)),
                          Text('View recent event stream or export system diagnostics', style: HsText.caption),
                        ],
                      ),
                      GlassButton(
                        label: 'Export',
                        height: 38,
                        fontSize: 13,
                        variant: GlassButtonVariant.secondary,
                        onPressed: () => _showDiagnosticsDialog(context),
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

  void _showDiagnosticsDialog(BuildContext context) async {
    final settings = ref.read(settingsProvider);
    final report = await AppLogger.instance.exportDiagnosticsText(
      deviceName: settings.deviceName,
    );

    if (!context.mounted) return;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: HsColors.bgRaised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: HsColors.glassStroke),
          ),
          title: Text('Diagnostics & Logs', style: HsText.title),
          content: SizedBox(
            width: 600,
            height: 400,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: HsColors.glassStroke),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  report,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Colors.white70,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
          actions: [
            GlassButton(
              label: 'Copy to Clipboard',
              variant: GlassButtonVariant.secondary,
              height: 36,
              fontSize: 12,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: report));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Diagnostics report copied to clipboard')),
                );
                Navigator.of(ctx).pop();
              },
            ),
            const SizedBox(width: 8),
            GlassButton(
              label: 'Close',
              variant: GlassButtonVariant.ghost,
              height: 36,
              fontSize: 12,
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        );
      },
    );
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
