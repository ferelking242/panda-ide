import 'dart:io';

class AlpineSetup {
  static String? locateProotBinary(String rootfsDir) {
    final candidates = <String>[
      '$rootfsDir/proot',
      '$rootfsDir/bin/proot',
      '$rootfsDir/rootfs/proot',
      '$rootfsDir/rootfs/bin/proot',
    ];

    for (final candidate in candidates) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }

    return null;
  }
}
