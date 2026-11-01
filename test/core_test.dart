import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:hotshare/core/engine/engine_api.dart';
import 'package:hotshare/core/platform/share_target_service.dart';
import 'package:hotshare/core/security/pairing.dart';
import 'package:hotshare/core/storage/storage_helper.dart';
import 'package:hotshare/core/storage/storage_resolver.dart';
import 'package:hotshare/core/transfer/incoming_transfer.dart';
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

  group('Pairing & Security', () {
    test('generatePairingCode produces 6 digits', () {
      final code = PairingSecurity.generatePairingCode();
      expect(code.length, 6);
      expect(int.tryParse(code), isNotNull);
    });

    test('computePairingProof produces deterministic HMAC', () {
      final nonceC = utf8.encode('nonce-client-1234');
      final nonceS = utf8.encode('nonce-server-5678');
      final pubKeyC = utf8.encode('pubkey-client-bytes');

      final proof1 = PairingSecurity.computePairingProof(
        code: '123456',
        nonceC: nonceC,
        nonceS: nonceS,
        pubKeyC: pubKeyC,
      );

      final proof2 = PairingSecurity.computePairingProof(
        code: '123456',
        nonceC: nonceC,
        nonceS: nonceS,
        pubKeyC: pubKeyC,
      );

      final proofWrongCode = PairingSecurity.computePairingProof(
        code: '654321',
        nonceC: nonceC,
        nonceS: nonceS,
        pubKeyC: pubKeyC,
      );

      expect(proof1, equals(proof2));
      expect(proof1, isNot(equals(proofWrongCode)));
    });

    test('deriveSasWords produces exactly 4 words and is order-independent for keys', () {
      final keyA = utf8.encode('alice-public-key');
      final keyB = utf8.encode('bob-public-key');
      final nonceC = utf8.encode('nonce-c');
      final nonceS = utf8.encode('nonce-s');

      final sas1 = PairingSecurity.deriveSasWords(
        pubKeyC: keyA,
        pubKeyS: keyB,
        nonceC: nonceC,
        nonceS: nonceS,
      );

      final sas2 = PairingSecurity.deriveSasWords(
        pubKeyC: keyB,
        pubKeyS: keyA,
        nonceC: nonceC,
        nonceS: nonceS,
      );

      expect(sas1.length, 4);
      expect(sas1, equals(sas2));
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

      const openPairing = OpenPairingWindowCommand();
      expect(openPairing, isA<EngineCommand>());

      const submitCode = SubmitPairingCodeCommand('123456');
      expect(submitCode.code, '123456');
    });
  });

  group('StorageResolver & File Kinds', () {
    test('classifyFileKind identifies extensions accurately', () {
      expect(StorageResolver.classifyFileKind('photo.JPG'), 'image');
      expect(StorageResolver.classifyFileKind('movie.mkv'), 'video');
      expect(StorageResolver.classifyFileKind('song.flac'), 'audio');
      expect(StorageResolver.classifyFileKind('report.pdf'), 'document');
      expect(StorageResolver.classifyFileKind('archive.zip'), 'archive');
      expect(StorageResolver.classifyFileKind('binary.bin'), 'other');
      expect(StorageResolver.classifyFileKind('no_extension'), 'other');
    });
  });

  group('ShareTargetService', () {
    test('can instantiate and deliver CLI arguments', () async {
      final service = ShareTargetService.instance;
      final future = service.sharedFilesStream.first;
      service.deliverCommandLineFiles(['test_file1.txt', 'test_file2.pdf']);
      final received = await future;
      expect(received, ['test_file1.txt', 'test_file2.pdf']);
    });
  });

  group('IncomingTransfer & Checksums', () {
    test('computes SHA-256 correctly across chunks', () async {
      final tempDir = Directory.systemTemp.createTempSync('hotshare_sha_test');
      try {
        final f = File('${tempDir.path}${Platform.pathSeparator}test.bin');
        final sink = f.openWrite();
        final inc = IncomingTransfer(
          id: 'test-1',
          name: 'test.bin',
          size: 10,
          file: f,
          sink: sink,
          enableChecksum: true,
        );

        final chunk1 = [1, 2, 3, 4, 5];
        final chunk2 = [6, 7, 8, 9, 10];
        inc.addChunk(chunk1);
        inc.addChunk(chunk2);

        await sink.close();
        final sha = inc.finalizeChecksum();

        // Compare with expected sha256 of [1..10]
        final expectedDigest = crypto.sha256.convert([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]).toString();
        expect(sha, expectedDigest);
        expect(inc.received, 10);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('resumption offset initializes correctly', () async {
      final tempDir = Directory.systemTemp.createTempSync('hotshare_resume_test');
      try {
        final f = File('${tempDir.path}${Platform.pathSeparator}test.bin');
        final sink = f.openWrite();
        final inc = IncomingTransfer(
          id: 'test-2',
          name: 'test.bin',
          size: 100,
          file: f,
          sink: sink,
          offset: 40,
        );
        expect(inc.offset, 40);
        expect(inc.received, 40);
        await sink.close();
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}
