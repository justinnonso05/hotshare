import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hotshare/core/engine/engine_api.dart';
import 'package:hotshare/core/storage/storage_helper.dart';
import 'package:hotshare/core/utils/formatters.dart';

void main() {
  group('Formatters', () {
    test('formatBytes formats bytes correctly', () {
      expect(formatBytes(500), '500 B');
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1024 * 1024 * 5), '5.0 MB');
      expect(formatBytes(1024 * 1024 * 1024 * 2), '2.00 GB');
    });
  });

  group('Storage Helpers', () {
    test('sanitizeFileName removes illegal characters and paths', () {
      expect(sanitizeFileName('test/path/to/file.txt'), 'file.txt');
      expect(sanitizeFileName('windows\\path\\to\\file.txt'), 'file.txt');
      expect(sanitizeFileName('bad:file*name?.txt'), 'bad_file_name_.txt');
      expect(sanitizeFileName(''), 'file');
    });

    test('createUniqueFile generates non-colliding names', () {
      final tempDir = Directory.systemTemp.createTempSync('hotshare_test');
      try {
        final f1 = createUniqueFile(tempDir, 'sample.txt');
        f1.writeAsStringSync('hello');

        final f2 = createUniqueFile(tempDir, 'sample.txt');
        expect(f2.path.endsWith('sample (1).txt'), isTrue);

        f2.writeAsStringSync('hello 2');
        final f3 = createUniqueFile(tempDir, 'sample.txt');
        expect(f3.path.endsWith('sample (2).txt'), isTrue);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  group('Engine API', () {
    test('commands can be instantiated', () {
      const start = StartServerCommand(port: 8080);
      expect(start.port, 8080);

      const connect = ConnectCommand(host: '192.168.43.1');
      expect(connect.host, '192.168.43.1');

      const send = SendFilesCommand(['file1.jpg', 'file2.pdf']);
      expect(send.paths.length, 2);

      const autoReconnect = SetAutoReconnectCommand(true);
      expect(autoReconnect.enabled, isTrue);
    });
  });
}
