import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/platform/device_name_service.dart';

/// Application configuration and preferences.
class AppSettings {
  final String deviceName;
  final bool autoAcceptTrusted;
  final bool pauseReceiving;
  final String? saveRootWindows;
  final String androidSaveMode; // 'byType' or 'downloads'
  final String organiseBy; // 'none', 'type', 'date', 'device'
  final bool keepPartials;
  final int historyRetentionDays;
  final bool autoReconnect;
  final String theme; // 'dark', 'light', 'system'
  final bool reduceTransparency;
  final bool reduceMotion;
  final bool verifyIntegrity;
  final int chunkSizeKb;

  const AppSettings({
    this.deviceName = '',
    this.autoAcceptTrusted = true,
    this.pauseReceiving = false,
    this.saveRootWindows,
    this.androidSaveMode = 'byType',
    this.organiseBy = 'none',
    this.keepPartials = false,
    this.historyRetentionDays = 90,
    this.autoReconnect = true,
    this.theme = 'dark',
    this.reduceTransparency = false,
    this.reduceMotion = false,
    this.verifyIntegrity = true,
    this.chunkSizeKb = 256,
  });

  AppSettings copyWith({
    String? deviceName,
    bool? autoAcceptTrusted,
    bool? pauseReceiving,
    String? saveRootWindows,
    String? androidSaveMode,
    String? organiseBy,
    bool? keepPartials,
    int? historyRetentionDays,
    bool? autoReconnect,
    String? theme,
    bool? reduceTransparency,
    bool? reduceMotion,
    bool? verifyIntegrity,
    int? chunkSizeKb,
  }) {
    return AppSettings(
      deviceName: deviceName ?? this.deviceName,
      autoAcceptTrusted: autoAcceptTrusted ?? this.autoAcceptTrusted,
      pauseReceiving: pauseReceiving ?? this.pauseReceiving,
      saveRootWindows: saveRootWindows ?? this.saveRootWindows,
      androidSaveMode: androidSaveMode ?? this.androidSaveMode,
      organiseBy: organiseBy ?? this.organiseBy,
      keepPartials: keepPartials ?? this.keepPartials,
      historyRetentionDays: historyRetentionDays ?? this.historyRetentionDays,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      theme: theme ?? this.theme,
      reduceTransparency: reduceTransparency ?? this.reduceTransparency,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      verifyIntegrity: verifyIntegrity ?? this.verifyIntegrity,
      chunkSizeKb: chunkSizeKb ?? this.chunkSizeKb,
    );
  }
}

/// State notifier managing persisted settings with SharedPreferences.
class SettingsNotifier extends Notifier<AppSettings> {
  static const _keyPrefix = 'hotshare_pref_';

  @override
  AppSettings build() {
    _loadFromPrefs();
    return const AppSettings();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString('${_keyPrefix}deviceName');
    String effectiveName;
    if (savedName == null || savedName.trim().isEmpty) {
      effectiveName = await DeviceNameService.detectDeviceName();
      await prefs.setString('${_keyPrefix}deviceName', effectiveName);
    } else {
      effectiveName = savedName;
    }

    state = AppSettings(
      deviceName: effectiveName,
      autoAcceptTrusted:
          prefs.getBool('${_keyPrefix}autoAcceptTrusted') ?? true,
      pauseReceiving: prefs.getBool('${_keyPrefix}pauseReceiving') ?? false,
      saveRootWindows: prefs.getString('${_keyPrefix}saveRootWindows'),
      androidSaveMode:
          prefs.getString('${_keyPrefix}androidSaveMode') ?? 'byType',
      organiseBy: prefs.getString('${_keyPrefix}organiseBy') ?? 'none',
      keepPartials: prefs.getBool('${_keyPrefix}keepPartials') ?? false,
      historyRetentionDays:
          prefs.getInt('${_keyPrefix}historyRetentionDays') ?? 90,
      autoReconnect: prefs.getBool('${_keyPrefix}autoReconnect') ?? true,
      theme: prefs.getString('${_keyPrefix}theme') ?? 'dark',
      reduceTransparency:
          prefs.getBool('${_keyPrefix}reduceTransparency') ?? false,
      reduceMotion: prefs.getBool('${_keyPrefix}reduceMotion') ?? false,
      verifyIntegrity: prefs.getBool('${_keyPrefix}verifyIntegrity') ?? true,
      chunkSizeKb: prefs.getInt('${_keyPrefix}chunkSizeKb') ?? 256,
    );
  }

  Future<void> update(AppSettings Function(AppSettings current) updater) async {
    final updated = updater(state);
    state = updated;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${_keyPrefix}deviceName', updated.deviceName);
    await prefs.setBool(
        '${_keyPrefix}autoAcceptTrusted', updated.autoAcceptTrusted);
    await prefs.setBool('${_keyPrefix}pauseReceiving', updated.pauseReceiving);
    if (updated.saveRootWindows != null) {
      await prefs.setString(
          '${_keyPrefix}saveRootWindows', updated.saveRootWindows!);
    }
    await prefs.setString(
        '${_keyPrefix}androidSaveMode', updated.androidSaveMode);
    await prefs.setString('${_keyPrefix}organiseBy', updated.organiseBy);
    await prefs.setBool('${_keyPrefix}keepPartials', updated.keepPartials);
    await prefs.setInt(
        '${_keyPrefix}historyRetentionDays', updated.historyRetentionDays);
    await prefs.setBool('${_keyPrefix}autoReconnect', updated.autoReconnect);
    await prefs.setString('${_keyPrefix}theme', updated.theme);
    await prefs.setBool(
        '${_keyPrefix}reduceTransparency', updated.reduceTransparency);
    await prefs.setBool('${_keyPrefix}reduceMotion', updated.reduceMotion);
    await prefs.setBool(
        '${_keyPrefix}verifyIntegrity', updated.verifyIntegrity);
    await prefs.setInt('${_keyPrefix}chunkSizeKb', updated.chunkSizeKb);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
