import 'dart:io';
import 'package:flutter/services.dart';

/// Detects the native host device name (e.g. "Justin-PC" on Windows or
/// "Redmi Note 13" / "Pixel 8" on Android).
class DeviceNameService {
  static const MethodChannel _channel = MethodChannel('com.hotshare.app/share_target');

  static Future<String> detectDeviceName() async {
    try {
      if (Platform.isWindows) {
        final hostname = Platform.localHostname.trim();
        if (hostname.isNotEmpty) {
          return hostname;
        }
        return 'Windows PC';
      }

      if (Platform.isAndroid) {
        final name = await _channel.invokeMethod<String>('getDeviceName');
        if (name != null && name.trim().isNotEmpty) {
          return name.trim();
        }
        return 'Android Phone';
      }
    } catch (_) {}

    return Platform.isWindows ? 'Windows PC' : 'Android Phone';
  }
}
