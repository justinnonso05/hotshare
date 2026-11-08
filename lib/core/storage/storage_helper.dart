import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Resolves the default HotShare save folder on the current platform.
Future<Directory> getHotShareSaveDirectory() async {
  final Directory base;
  if (Platform.isAndroid) {
    base = (await getExternalStorageDirectory()) ??
        await getApplicationDocumentsDirectory();
  } else {
    base = (await getDownloadsDirectory()) ??
        await getApplicationDocumentsDirectory();
  }
  final dir = Directory('${base.path}${Platform.pathSeparator}HotShare');
  await dir.create(recursive: true);
  return dir;
}

/// Sanitizes a file name by removing paths and characters rejected by OS filesystems.
String sanitizeFileName(String name) {
  final last = name.split(RegExp(r'[\\/]')).last;
  final clean = last.replaceAll(RegExp(r'[<>:"|?*\x00-\x1f]'), '_').trim();
  return clean.isEmpty ? 'file' : clean;
}

/// Sanitizes a relative file path preserving subdirectory structure while preventing directory traversal.
String sanitizeRelativePath(String rawPath) {
  final normalized = rawPath.replaceAll('\\', '/');
  final parts = normalized
      .split('/')
      .where((p) => p.isNotEmpty && p != '.' && p != '..');

  final sanitizedParts = parts.map((part) {
    final clean = part.replaceAll(RegExp(r'[<>:"|?*\x00-\x1f]'), '_').trim();
    return clean.isEmpty ? '_' : clean;
  }).toList();

  if (sanitizedParts.isEmpty) {
    return 'file';
  }
  return sanitizedParts.join(Platform.pathSeparator);
}

/// Representation of an outgoing or incoming file item, supporting recursive directory structures.
class FilePayload {
  final File file;
  final String relativePath;
  final int size;

  const FilePayload({
    required this.file,
    required this.relativePath,
    required this.size,
  });
}

/// Expands a list of file/directory paths into flat [FilePayload] items with preserved relative paths.
Future<List<FilePayload>> expandPaths(List<String> paths) async {
  final payloads = <FilePayload>[];

  for (final rawPath in paths) {
    final cleanPath = rawPath.trim();
    if (cleanPath.isEmpty) continue;

    final type = await FileSystemEntity.type(cleanPath);
    if (type == FileSystemEntityType.directory) {
      final dir = Directory(cleanPath);
      final normalizedDir = dir.path.replaceAll('\\', '/');
      final segments = normalizedDir.split('/').where((s) => s.isNotEmpty).toList();
      final rootFolderName = segments.isNotEmpty ? segments.last : 'Folder';

      try {
        final entities = dir.listSync(recursive: true, followLinks: false);
        for (final entity in entities) {
          if (entity is File) {
            final entityNorm = entity.path.replaceAll('\\', '/');
            String subPath;
            if (entityNorm.startsWith(normalizedDir)) {
              subPath = entityNorm.substring(normalizedDir.length);
              if (subPath.startsWith('/')) {
                subPath = subPath.substring(1);
              }
            } else {
              subPath = entityNorm.split('/').last;
            }
            final relativePath = '$rootFolderName/$subPath';
            int size = 0;
            try {
              size = await entity.length();
            } catch (_) {}

            payloads.add(FilePayload(
              file: entity,
              relativePath: relativePath,
              size: size,
            ));
          }
        }
      } catch (_) {}
    } else if (type == FileSystemEntityType.file) {
      final file = File(cleanPath);
      final fileName = cleanPath.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).last;
      int size = 0;
      try {
        size = await file.length();
      } catch (_) {}
      payloads.add(FilePayload(
        file: file,
        relativePath: fileName,
        size: size,
      ));
    }
  }

  return payloads;
}

/// Generates a unique [File] inside [dir] by appending an incrementing index if a collision occurs.
File createUniqueFile(Directory dir, String name) {
  final sep = Platform.pathSeparator;
  var f = File('${dir.path}$sep$name');
  if (!f.existsSync()) return f;
  final dot = name.lastIndexOf('.');
  final base = dot > 0 ? name.substring(0, dot) : name;
  final ext = dot > 0 ? name.substring(dot) : '';
  var i = 1;
  while (f.existsSync()) {
    f = File('${dir.path}$sep$base ($i)$ext');
    i++;
  }
  return f;
}
