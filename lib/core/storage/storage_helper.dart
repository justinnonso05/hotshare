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
