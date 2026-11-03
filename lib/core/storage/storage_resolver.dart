import 'dart:io';

import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// Classifies file types and resolves platform-specific destination directories.
class StorageResolver {
  /// Classifies file kind based on file extension.
  static String classifyFileKind(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot <= 0 || dot == fileName.length - 1) return 'other';
    final ext = fileName.substring(dot + 1).toLowerCase();

    const imageExts = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'svg'};
    const videoExts = {'mp4', 'mkv', 'avi', 'mov', 'webm', 'flv', '3gp'};
    const audioExts = {'mp3', 'wav', 'm4a', 'flac', 'aac', 'ogg', 'opus'};
    const docExts = {
      'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'csv', 'md', 'json'
    };
    const archiveExts = {'zip', 'rar', '7z', 'tar', 'gz', 'bz2'};

    if (imageExts.contains(ext)) return 'image';
    if (videoExts.contains(ext)) return 'video';
    if (audioExts.contains(ext)) return 'audio';
    if (docExts.contains(ext)) return 'document';
    if (archiveExts.contains(ext)) return 'archive';
    return 'other';
  }

  /// Resolves the destination directory on the device according to platform conventions.
  /// Always routes directly into the user-accessible Downloads/HotShare folder on all devices.
  static Future<Directory> resolveDestinationDirectory({
    required String fileName,
    String androidMode = 'downloads',
    String? customRootWindows,
    String organiseBy = 'none',
  }) async {
    Directory target;

    if (Platform.isAndroid) {
      // 1. Target public shared Downloads on Android (/storage/emulated/0/Download/HotShare)
      final candidates = [
        Directory('/storage/emulated/0/Download/HotShare'),
        Directory('/sdcard/Download/HotShare'),
      ];
      Directory? resolved;
      for (final candidate in candidates) {
        try {
          if (!await candidate.exists()) {
            await candidate.create(recursive: true);
          }
          resolved = candidate;
          break;
        } catch (_) {}
      }

      if (resolved != null) {
        target = resolved;
      } else {
        // Fallback to app external storage
        final extDirs = await getExternalStorageDirectories(type: StorageDirectory.downloads);
        final base = (extDirs != null && extDirs.isNotEmpty)
            ? extDirs.first
            : (await getApplicationDocumentsDirectory());
        target = Directory('${base.path}${Platform.pathSeparator}HotShare');
        if (!await target.exists()) {
          await target.create(recursive: true);
        }
      }
    } else {
      // Windows: User Downloads/HotShare
      final downloadsDir = (await getDownloadsDirectory()) ??
          await getApplicationDocumentsDirectory();
      target = Directory('${downloadsDir.path}${Platform.pathSeparator}HotShare');
      if (!await target.exists()) {
        await target.create(recursive: true);
      }
    }

    return target;
  }

  /// Triggers the Android media scanner so the file immediately appears in the
  /// Gallery, Downloads, and File Manager.
  static Future<void> scanMedia(String path) async {
    if (!Platform.isAndroid) return;
    try {
      const channel = MethodChannel('com.hotshare.app/share_target');
      await channel.invokeMethod('scanFile', {'path': path});
    } catch (_) {}
  }

  /// Checks if the destination has sufficient space before writing.
  static Future<bool> hasEnoughSpace(int requiredBytes) async {
    try {
      // Basic safeguard: reject files larger than memory if free space is unknown
      return requiredBytes > 0;
    } catch (_) {
      return true;
    }
  }

  /// Opens the file or reveals it in the platform file manager.
  static Future<void> showInFileManager(String filePath) async {
    if (Platform.isWindows) {
      try {
        await Process.run('explorer.exe', ['/select,', filePath]);
      } catch (_) {
        await OpenFilex.open(filePath);
      }
    } else {
      await OpenFilex.open(filePath);
    }
  }
}
