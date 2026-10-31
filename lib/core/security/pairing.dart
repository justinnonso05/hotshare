import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;

/// Helpers for the one-time pairing flow, code verification proof, and SAS word derivation.
class PairingSecurity {
  static const List<String> _sasDictionary = [
    'anchor', 'apple', 'arrow', 'badge', 'beacon', 'breeze', 'bridge', 'button',
    'candle', 'castle', 'cherry', 'clover', 'comet', 'copper', 'coral', 'crater',
    'crystal', 'dolphin', 'dragon', 'eagle', 'ember', 'falcon', 'feather', 'flame',
    'forest', 'fossil', 'galaxy', 'garden', 'glacier', 'grape', 'harbor', 'haven',
    'hawk', 'hazel', 'island', 'jasper', 'jungle', 'kitten', 'lagoon', 'lantern',
    'lizard', 'lotus', 'lunar', 'magnet', 'mango', 'maple', 'marble', 'meadow',
    'meteor', 'monkey', 'moss', 'nebula', 'oasis', 'ocean', 'olive', 'orbit',
    'orchid', 'owl', 'panda', 'parrot', 'pearl', 'pebble', 'pepper', 'phoenix',
    'planet', 'polar', 'prism', 'quartz', 'quiver', 'rabbit', 'radar', 'rainbow',
    'raven', 'reef', 'river', 'robin', 'rocket', 'ruby', 'saddle', 'sailor',
    'salmon', 'shadow', 'shield', 'silver', 'solar', 'spark', 'sparrow', 'spring',
    'spruce', 'star', 'stone', 'stream', 'summit', 'tiger', 'timber', 'topaz',
    'torch', 'tulip', 'tunnel', 'turtle', 'valley', 'velvet', 'vessel', 'violet',
    'volcano', 'walnut', 'willow', 'wind', 'winter', 'wizard', 'wolf', 'zenith',
    'amber', 'azure', 'bliss', 'canyon', 'cedar', 'chime', 'cider', 'cloud',
    'clover', 'cobalt', 'cosmos', 'cradle', 'creek', 'dawn', 'drift', 'dune',
    'echo', 'elm', 'fern', 'flare', 'flint', 'frost', 'garnet', 'geyser',
    'glen', 'glow', 'grove', 'halo', 'heath', 'hero', 'honey', 'horizon',
    'iris', 'isle', 'ivy', 'jewel', 'juniper', 'kelp', 'knight', 'lake',
    'leaf', 'light', 'lily', 'lime', 'lynx', 'marsh', 'mesa', 'mist',
    'moon', 'morning', 'moss', 'mountain', 'myrtle', 'nectar', 'nest', 'nova',
    'oak', 'opal', 'orbit', 'otter', 'peak', 'petal', 'pine', 'plume',
    'pond', 'poplar', 'prairie', 'prism', 'quarry', 'rain', 'rapid', 'raven',
    'ridge', 'ripple', 'root', 'rose', 'sage', 'sand', 'sapphire', 'sea',
    'serene', 'shimmer', 'shore', 'sky', 'slate', 'sleet', 'snow', 'solace',
    'sound', 'spruce', 'stone', 'storm', 'sun', 'surf', 'tide', 'trail',
    'tree', 'vale', 'valley', 'vigor', 'wave', 'wind', 'wood', 'yew'
  ];

  /// Generates a random 6-digit numeric pairing code.
  static String generatePairingCode() {
    final rand = Random.secure();
    final code = 100000 + rand.nextInt(900000);
    return code.toString();
  }

  /// Generates a random 16-byte hex secret.
  static String generatePairSecret() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Calculates HMAC-SHA256 proof for the pairing code.
  static String computePairingProof({
    required String code,
    required List<int> nonceC,
    required List<int> nonceS,
    required List<int> pubKeyC,
  }) {
    final keyBytes = utf8.encode(code);
    final data = <int>[...nonceC, ...nonceS, ...pubKeyC];
    final hmac = crypto.Hmac(crypto.sha256, keyBytes);
    final digest = hmac.convert(data);
    return digest.toString();
  }

  /// Derives a 4-word Short Authentication String (SAS) verification phrase.
  static List<String> deriveSasWords({
    required List<int> pubKeyC,
    required List<int> pubKeyS,
    required List<int> nonceC,
    required List<int> nonceS,
  }) {
    // Sort public keys deterministically
    final sortedKeys = [pubKeyC, pubKeyS]..sort((a, b) {
      for (int i = 0; i < min(a.length, b.length); i++) {
        if (a[i] != b[i]) return a[i].compareTo(b[i]);
      }
      return a.length.compareTo(b.length);
    });

    final data = <int>[
      ...sortedKeys[0],
      ...sortedKeys[1],
      ...nonceC,
      ...nonceS,
    ];

    final hmac = crypto.Hmac(crypto.sha256, utf8.encode('hotshare-sas-v2'));
    final digestBytes = hmac.convert(data).bytes;

    final words = <String>[];
    for (int i = 0; i < 4; i++) {
      final index = digestBytes[i] % _sasDictionary.length;
      words.add(_sasDictionary[index]);
    }
    return words;
  }
}
