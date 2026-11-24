import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the committed iOS toolchain state migrated in issue #52: the
/// Flutter tool drives iOS plugins through Swift Package Manager
/// (`FlutterGeneratedPluginSwiftPackage`), and the committed Xcode project
/// carries no CocoaPods integration that `pod install` could resurrect.
///
/// CocoaPods scaffolding (`ios/Podfile`, `ios/Podfile.lock`, the two optional
/// `#include?` lines in `Flutter/{Debug,Release}.xcconfig`) is retained as an
/// inert, documented fallback — the guard pins it inert.
///
/// All paths are committed files, so the test only needs the checkout root
/// (`flutter test` runs from it; see flutter_test_lock_test.dart for the
/// `Directory.current` precedent).
File repoFile(String relativePath) =>
    File.fromUri(Directory.current.uri.resolve('ios/$relativePath'));

String read(String relativePath) => repoFile(relativePath).readAsStringSync();

void main() {
  group('ios committed state (issue #52): Swift Package Manager pure', () {
    test(
      'pbxproj integrates plugins via FlutterGeneratedPluginSwiftPackage',
      () {
        final pbxproj = read('Runner.xcodeproj/project.pbxproj');

        // The SPM references are what "pure SPM" means — they must stay.
        expect(pbxproj, contains('XCLocalSwiftPackageReference'));
        expect(pbxproj, contains('XCSwiftPackageProductDependency'));
        expect(
          pbxproj,
          contains('/* FlutterGeneratedPluginSwiftPackage in Frameworks */'),
        );
      },
    );

    test('pbxproj carries no CocoaPods integration remnants', () {
      final pbxproj = read('Runner.xcodeproj/project.pbxproj');

      expect(
        pbxproj,
        isNot(contains('Pods_')),
        reason: 'pods frameworks/groups',
      );
      expect(
        pbxproj,
        isNot(contains('Pods-Runner')),
        reason: 'pods xcconfig file refs',
      );
      expect(pbxproj, isNot(contains('Check Pods Manifest.lock')));
      expect(pbxproj, isNot(contains('Embed Pods Frameworks')));
      expect(pbxproj, isNot(contains('Copy Pods Resources')));
      expect(
        pbxproj,
        isNot(contains('Target Support Files')),
        reason: 'pods xcconfig file references (Target Support Files)',
      );
    });

    test('workspace references Runner only (no Pods project)', () {
      final workspace = read('Runner.xcworkspace/contents.xcworkspacedata');

      expect(workspace, isNot(contains('Pods/Pods.xcodeproj')));
      expect(workspace, contains('Runner.xcodeproj'));
    });

    test('xcconfigs keep only the tool-managed optional pod include', () {
      final debug = read('Flutter/Debug.xcconfig');
      final release = read('Flutter/Release.xcconfig');

      // The Flutter tool re-adds `#include? "Pods/..."` while a Podfile and
      // Podfile.lock exist; they must stay optional so builds from a clean
      // clone never need a generated Pods/ target-support file.
      expect(
        debug,
        contains('#include? "Pods/Target Support Files/Pods-Runner/'),
      );
      expect(
        release,
        contains('#include? "Pods/Target Support Files/Pods-Runner/'),
      );
      for (final config in [debug, release]) {
        expect(
          RegExp(r'^#include "Pods/', multiLine: true).allMatches(config),
          isEmpty,
          reason: 'optional #include? only — a hard include requires Pods/',
        );
        expect(
          config.contains('Pods-RunnerTests'),
          isFalse,
          reason: 'the RunnerTests pods config must not return',
        );
      }
    });

    test(
      'retained Podfile is an inert fallback (no pods, no user integration)',
      () {
        final podfile = read('Podfile');

        // Without this line CocoaPods re-integrates Runner on every
        // `pod install` and the hybrid SPM/pods state returns (issue #52).
        expect(
          podfile,
          contains("install! 'cocoapods', :integrate_targets => false"),
        );
        expect(
          RegExp(r'^\s*pod\s', multiLine: true).allMatches(podfile),
          isEmpty,
          reason: 'no pod declarations while SPM is the active manager',
        );
        expect(podfile, isNot(contains('flutter_install_all_ios_pods')));
      },
    );

    test('retained Podfile.lock declares no pods', () {
      final lock = read('Podfile.lock');

      expect(
        RegExp(r'^\s*- ', multiLine: true).allMatches(lock),
        isEmpty,
        reason: 'no dependency lines: no plugin pods while SPM is active',
      );
      expect(lock, contains('COCOAPODS:'));
    });

    test('scheme keeps the SPM prepare pre-action', () {
      final scheme = read(
        'Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme',
      );

      // The committed scheme must keep the tool's SPM prepare pre-action
      // (`xcode_backend.sh prepare`, committed since the initial scaffold):
      // losing it breaks framework preparation before xcodebuild resolves
      // packages.
      expect(scheme, contains('PreActions'));
      expect(scheme, contains('xcode_backend.sh'));
    });
  });

  group('retained CocoaPods scaffolding stays consistent (issue #52)', () {
    test('Podfile and Podfile.lock exist as the committed fallback', () {
      expect(
        repoFile('Podfile').existsSync(),
        isTrue,
        reason: 'the committed CocoaPods fallback must stay (issue #52)',
      );
      expect(
        repoFile('Podfile.lock').existsSync(),
        isTrue,
        reason: 'the committed CocoaPods fallback must stay (issue #52)',
      );
    });

    test('Podfile.lock checksum matches the Podfile content', () {
      final lock = read('Podfile.lock');
      final checksum = RegExp(
        r'^PODFILE CHECKSUM: ([0-9a-f]{40})$',
        multiLine: true,
      ).firstMatch(lock)?.group(1);
      expect(
        checksum,
        isNotNull,
        reason: 'PODFILE CHECKSUM present in Podfile.lock',
      );

      // cocoapods-core writes PODFILE CHECKSUM as the SHA-1 of the Podfile
      // file content. A Podfile edit without regenerating the lock would make
      // the next flutter build rewrite the lock and dirty the tree — catch
      // the drift here instead.
      expect(
        sha1Hex(repoFile('Podfile').readAsBytesSync()),
        checksum,
        reason: 'Podfile and Podfile.lock are out of sync; regenerate the lock',
      );
    });

    test('sha1Hex matches the SHA-1 vectors and detects checksum drift', () {
      // Known SHA-1 vectors (empty input and "abc").
      expect(sha1Hex(const []), 'da39a3ee5e6b4b0d3255bfef95601890afd80709');
      expect(
        sha1Hex('abc'.codeUnits),
        'a9993e364706816aba3e25717850c26c9cd0d89d',
      );

      // Drift catch: a Podfile whose SHA-1 differs from the lock's checksum
      // line must be reported, so a "consistent" line and a drifted line are
      // handled differently (one matches, one does not).
      final dir = Directory.systemTemp.createTempSync('murdoku_podfile_drift');
      addTearDown(() => dir.deleteSync(recursive: true));
      final podfile = File('${dir.path}/Podfile')
        ..writeAsStringSync('legacy pods content\n');
      final consistentChecksum = sha1Hex(podfile.readAsBytesSync());
      final driftedChecksum = consistentChecksum == '0' * 40
          ? 'a' * 40
          : '0' * 40;
      expect(driftedChecksum, isNot(sha1Hex(podfile.readAsBytesSync())));
      expect(consistentChecksum, sha1Hex(podfile.readAsBytesSync()));
    });
  });
}

/// Plain SHA-1 (RFC 3174), matching `Digest::SHA1.hexdigest` — the algorithm
/// cocoapods-core 1.17 uses for `PODFILE CHECKSUM`. Reimplemented in pure Dart
/// so this guard needs no ruby binary and no new package dependency.
String sha1Hex(List<int> bytes) {
  // Pad to length ≡ 56 mod 64, then append the 64-bit message length.
  final int bitLength = bytes.length * 8;
  final message = <int>[...bytes, 0x80];
  while (message.length % 64 != 56) {
    message.add(0);
  }
  for (int shift = 56; shift >= 0; shift -= 8) {
    message.add((bitLength >> shift) & 0xff);
  }

  final h = <int>[0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0];
  for (var block = 0; block < message.length; block += 64) {
    final w = List<int>.filled(80, 0);
    for (var i = 0; i < 16; i++) {
      w[i] =
          (message[block + 4 * i] << 24) |
          (message[block + 4 * i + 1] << 16) |
          (message[block + 4 * i + 2] << 8) |
          message[block + 4 * i + 3];
    }
    for (var i = 16; i < 80; i++) {
      final value = w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16];
      w[i] = ((value << 1) | (value >>> 31)) & 0xffffffff;
    }

    var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4];
    for (var i = 0; i < 80; i++) {
      final (int f, int k) = switch (i) {
        < 20 => ((b & c) | ((~b & 0xffffffff) & d), 0x5A827999),
        < 40 => (b ^ c ^ d, 0x6ED9EBA1),
        < 60 => ((b & c) | (b & d) | (c & d), 0x8F1BBCDC),
        _ => (b ^ c ^ d, 0xCA62C1D6),
      };
      final temp = (((a << 5) | (a >>> 27)) + f + e + k + w[i]) & 0xffffffff;
      e = d;
      d = c;
      c = ((b << 30) | (b >>> 2)) & 0xffffffff;
      b = a;
      a = temp;
    }
    h[0] = (h[0] + a) & 0xffffffff;
    h[1] = (h[1] + b) & 0xffffffff;
    h[2] = (h[2] + c) & 0xffffffff;
    h[3] = (h[3] + d) & 0xffffffff;
    h[4] = (h[4] + e) & 0xffffffff;
  }

  return h.map((word) => word.toRadixString(16).padLeft(8, '0')).join();
}
