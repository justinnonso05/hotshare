import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform/share_target_service.dart';
import '../data/settings/app_settings.dart';
import '../ui/design_system/design_system.dart';
import '../ui/features/devices/devices_screen.dart';
import '../ui/features/history/history_screen.dart';
import '../ui/features/nearby/nearby_screen.dart';
import '../ui/features/settings/settings_screen.dart';
import '../ui/features/share_target/quick_send_sheet.dart';
import '../ui/features/splash/splash_screen.dart';
import 'shell_desktop.dart';
import 'shell_mobile.dart';

/// Root application widget. Sets up the Ember Glass theme and routes to the
/// platform-appropriate shell.
class HotShareApp extends ConsumerStatefulWidget {
  const HotShareApp({super.key});

  @override
  ConsumerState<HotShareApp> createState() => _HotShareAppState();
}

class _HotShareAppState extends ConsumerState<HotShareApp> {
  bool _showSplash = true;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final brightness = _resolveBrightness(settings.theme, context);

    return MaterialApp(
      title: 'HotShare',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(brightness),
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: _showSplash
            ? HotShareSplashScreen(
                onFinish: () => setState(() => _showSplash = false),
              )
            : AppBackground(
                key: const ValueKey('app_shell'),
                reduceMotion: settings.reduceMotion,
                child: _PlatformShell(settings: settings),
              ),
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: Colors.transparent,
      colorScheme: ColorScheme.fromSeed(
        seedColor: HsColors.accentPrimary,
        brightness: brightness,
        surface: HsColors.bgRaised,
      ),
      useMaterial3: true,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      dividerColor: HsColors.glassStroke,
      chipTheme: ChipThemeData(
        backgroundColor: HsColors.glassFillStrong,
        labelStyle: const TextStyle(color: HsColors.textSecondary, fontSize: 13),
        side: const BorderSide(color: HsColors.glassStroke, width: 0.5),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return HsColors.accentPrimary;
          }
          return HsColors.textTertiary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return HsColors.accentPrimary.withAlpha(60);
          }
          return HsColors.glassFillStrong;
        }),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: HsColors.bgRaised,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: HsText.headline,
        contentTextStyle: HsText.body,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(HsColors.radiusCard)),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: HsColors.bgRaised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(HsColors.radiusCard),
          ),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: HsColors.bgRaised,
        contentTextStyle: HsText.body,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(HsColors.radiusSmall)),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Brightness _resolveBrightness(String theme, BuildContext context) {
    switch (theme) {
      case 'light':
        return Brightness.light;
      case 'dark':
        return Brightness.dark;
      default:
        return MediaQuery.platformBrightnessOf(context);
    }
  }
}

class _PlatformShell extends ConsumerStatefulWidget {
  final AppSettings settings;

  const _PlatformShell({required this.settings});

  @override
  ConsumerState<_PlatformShell> createState() => _PlatformShellState();
}

class _PlatformShellState extends ConsumerState<_PlatformShell> {
  StreamSubscription<List<String>>? _shareSub;

  @override
  void initState() {
    super.initState();
    _shareSub = ShareTargetService.instance.sharedFilesStream.listen((paths) {
      if (paths.isNotEmpty && mounted) {
        QuickSendSheet.show(context, paths);
      }
    });
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isWindows) {
      return DesktopShell(
        railItems: desktopRailItems,
        pages: const [
          NearbyScreen(),
          HistoryScreen(),
          DevicesScreen(),
          SettingsScreen(),
        ],
      );
    }

    return MobileShell(
      pages: const [
        NearbyScreen(),
        HistoryScreen(),
        DevicesScreen(),
        SettingsScreen(),
      ],
    );
  }
}
