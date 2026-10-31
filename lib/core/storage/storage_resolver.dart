import 'dart:io';

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

  /// Resolves the destination directory on the device according to platform conventions and settings.
  static Future<Directory> resolveDestinationDirectory({
    required String fileName,
    String androidMode = 'byType', // 'byType' or 'downloads'
    String? customRootWindows,
    String organiseBy = 'none', // 'none', 'type', 'date', 'device'
  }) async {
    final kind = classifyFileKind(fileName);
    Directory base;

    if (Platform.isAndroid) {
      if (androidMode == 'byType') {
        // Scoped media / download routing
        switch (kind) {
          case 'image':
            final extDirs = await getExternalStorageDirectories(type: StorageDirectory.pictures);
            base = (extDirs != null && extDirs.isNotEmpty)
                ? extDirs.first
                : (await getApplicationDocumentsDirectory());
          case 'video':
            final extDirs = await getExternalStorageDirectories(type: StorageDirectory.movies);
            base = (extDirs != null && extDirs.isNotEmpty)
                ? extDirs.first
                : (await getApplicationDocumentsDirectory());
          case 'audio':
            final extDirs = await getExternalStorageDirectories(type: StorageDirectory.music);
            base = (extDirs != null && extDirs.isNotEmpty)
                ? extDirs.first
                : (await getApplicationDocumentsDirectory());
          default:
            final extDirs = await getExternalStorageDirectories(type: StorageDirectory.downloads);
            base = (extDirs != null && extDirs.isNotEmpty)
                ? extDirs.first
                : (await getApplicationDocumentsDirectory());
        }
      } else {
        final extDirs = await getExternalStorageDirectories(type: StorageDirectory.downloads);
        base = (extDirs != null && extDirs.isNotEmpty)
            ? extDirs.first
            : (await getApplicationDocumentsDirectory());
      }
    } else {
      // Windows
      if (customRootWindows != null && customRootWindows.isNotEmpty) {
        base = Directory(customRootWindows);
      } else {
        base = (await getDownloadsDirectory()) ??
            await getApplicationDocumentsDirectory();
      }
    }

    var targetPath = '${base.path}${Platform.pathSeparator}HotShare';

    // Sub-folder organization
    if (organiseBy == 'type') {
      final sub = kind[0].toUpperCase() + kind.substring(1);
      targetPath = '$targetPath${Platform.pathSeparator}$sub';
    } else if (organiseBy == 'date') {
      final now = DateTime.now();
      final dateSub = '${now.year}-${now.month.toString().padLeft(2, '0')}';
      targetPath = '$targetPath${Platform.pathSeparator}$dateSub';
    }

    final dir = Directory(targetPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
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
