import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Top-level callback for the foreground task isolate.
@pragma('vm:entry-point')
void startForegroundCallback() {
  FlutterForegroundTask.setTaskHandler(HotShareTaskHandler());
}

/// Minimal TaskHandler keeping the service and locks alive on Android.
class HotShareTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}

/// Helper managing Android foreground service, wake locks, and Wi-Fi locks.
class AndroidForegroundServiceManager {
  static bool _initialized = false;

  static Future<void> init() async {
    if (!Platform.isAndroid || _initialized) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'hotshare_service',
        channelName: 'HotShare Background Service',
        channelDescription:
            'Keeps HotShare connection and file transfers active in the background.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        enableVibration: false,
        playSound: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    _initialized = true;

    // Check & request notification permission
    final perm = await FlutterForegroundTask.checkNotificationPermission();
    if (perm != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    // Check & request battery optimization exemption
    final isIgnoring =
        await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    if (!isIgnoring) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
  }

  static Future<void> start() async {
    if (!Platform.isAndroid) return;
    await init();

    if (await FlutterForegroundTask.isRunningService) return;

    await FlutterForegroundTask.startService(
      notificationTitle: 'HotShare is ready',
      notificationText: 'Listening for incoming transfers over local hotspot',
      callback: startForegroundCallback,
    );
  }

  static Future<void> updateNotification({
    required String title,
    required String text,
  }) async {
    if (!Platform.isAndroid) return;
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: text,
      );
    }
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }
}
