import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/flutter_test_lock.dart';

var _uniqueLockPathCounter = 0;

/// Lock path unique to this test run: the suite itself may already be running
/// under the default lock (`make quality`), so tests must never contend on it.
String uniqueLockPath() {
  final tag =
      '${DateTime.now().microsecondsSinceEpoch}_${_uniqueLockPathCounter++}';
  return '${Directory.current.path}/.dart_tool/'
      'flutter_test_lock_test_$tag.lock';
}

/// Deletes a test lock file once its assertions are done, so suite runs do
/// not accumulate lock files in `.dart_tool`.
void cleanupLock(String path) {
  addTearDown(() {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  });
}

/// Runs the lock CLI as a real subprocess; cross-process contention is the
/// behavior under test, so the lock is never acquired in this test process
/// except where a case explicitly does so, and no subprocess ever contends on
/// this checkout's default lock (they pass a unique `--lock-path` or run in
/// an ephemeral fake checkout).
Future<ProcessResult> runLock(List<String> args) {
  return Process.run('dart', [
    'tool/flutter_test_lock.dart',
    ...args,
  ], workingDirectory: Directory.current.path);
}

Future<Process> startedLock(List<String> args) {
  return Process.start('dart', [
    'tool/flutter_test_lock.dart',
    ...args,
  ], workingDirectory: Directory.current.path);
}

void main() {
  test('resolves the default lock inside the checkout .dart_tool', () {
    final lockPath = defaultLockPath();
    expect(lockPath, isNotNull);
    expect(lockPath!, contains(Directory.current.path));
    expect(
      lockPath,
      endsWith('.dart_tool${Platform.pathSeparator}flutter_test.lock'),
    );
  });

  test('findCheckoutRoot stops at the enclosing pubspec.yaml', () {
    final probe = Directory.systemTemp.createTempSync('murdoku_lock_root');
    addTearDown(() => probe.deleteSync(recursive: true));
    Directory('${probe.path}/a/b').createSync(recursive: true);
    File('${probe.path}/pubspec.yaml').writeAsStringSync('name: probe\n');

    final found = findCheckoutRoot(start: Directory('${probe.path}/a/b'));
    expect(found?.path, probe.path);
  });

  test('findCheckoutRoot returns null without a pubspec', () {
    final probe = Directory.systemTemp.createTempSync('murdoku_lock_root2');
    addTearDown(() => probe.deleteSync(recursive: true));
    Directory('${probe.path}/a').createSync(recursive: true);

    final found = findCheckoutRoot(start: Directory('${probe.path}/a'));
    expect(found, isNull);
  });

  test('refuses to lock outside any pubspec checkout', () async {
    // Without a pubspec.yaml up the chain there is no checkout root: the
    // wrapper must refuse (usage exit) instead of creating a machine-global
    // lock at the filesystem root.
    final probe = Directory.systemTemp.createTempSync('murdoku_lock_nomark');
    addTearDown(() => probe.deleteSync(recursive: true));

    final result = await Process.run('dart', [
      '${Directory.current.path}/tool/flutter_test_lock.dart',
      '--',
      'true',
    ], workingDirectory: probe.path);

    expect(result.exitCode, 2, reason: result.stderr.toString());
    expect(result.stderr, contains('pubspec'));
    expect(
      Directory('${probe.path}/.dart_tool').existsSync(),
      isFalse,
      reason: 'no lock file may be created without a checkout root',
    );
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('anchors the default lock at the enclosing pubspec checkout', () async {
    // An ephemeral fake checkout: a child started from its subdirectory must
    // resolve its default lock to the fake root's .dart_tool, exercising the
    // findCheckoutRoot wiring end to end — without touching or contending on
    // this checkout's default lock, which a `make quality` suite holds.
    final fake = Directory.systemTemp.createTempSync('murdoku_lock_fake');
    addTearDown(() => fake.deleteSync(recursive: true));
    Directory('${fake.path}/sub').createSync();
    File('${fake.path}/pubspec.yaml')
        .writeAsStringSync('name: fake_checkout\n');

    final result = await Process.run('dart', [
      '${Directory.current.path}/tool/flutter_test_lock.dart',
      '--',
      'true',
    ], workingDirectory: '${fake.path}/sub');

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(
      File('${fake.path}/.dart_tool/flutter_test.lock').existsSync(),
      isTrue,
      reason: 'the child must lock the pubspec-marked checkout, not cwd',
    );
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('forwards the child exit code', () async {
    final path = uniqueLockPath();
    cleanupLock(path);

    final failure = await runLock(['--lock-path=$path', '--', 'false']);
    final success = await runLock(['--lock-path=$path', '--', 'true']);

    expect(failure.exitCode, 1);
    expect(success.exitCode, 0);
    expect(File(path).existsSync(), isTrue);
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('serializes overlapping holders', () async {
    final path = uniqueLockPath();
    cleanupLock(path);

    // Hold the lock in-process so the ordering cannot invert on slow
    // subprocess startup: the child first proves it is queued (its stderr
    // wait notice) while the lock is held, then only runs after release.
    final lock = acquireCheckoutLock(
      path: path,
      timeout: const Duration(seconds: 30),
    );
    final child = await startedLock([
      '--lock-path=$path',
      '--timeout=20',
      '--',
      'true',
    ]);
    final childStderr = StringBuffer();
    child.stderr.transform(utf8.decoder).listen(childStderr.write);

    final handshake = Stopwatch()..start();
    while (!childStderr.toString().contains('waiting for it to finish')) {
      if (handshake.elapsed > const Duration(seconds: 15)) {
        fail('child never reported waiting for the held lock');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    // Keep holding well past the handshake; the child may only run at
    // release.
    final watch = Stopwatch()..start();
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    lock.release();

    expect(await child.exitCode, 0);
    expect(watch.elapsed, greaterThan(const Duration(milliseconds: 1400)));
    expect(childStderr.toString(), contains('waiting for it to finish'));
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('times out while the first holds', () async {
    final path = uniqueLockPath();
    cleanupLock(path);

    final first = await startedLock(['--lock-path=$path', '--', 'sleep', '5']);
    await Future<void>.delayed(const Duration(milliseconds: 500));

    final expired = await runLock([
      '--lock-path=$path',
      '--timeout=1',
      '--',
      'true',
    ]);
    final firstExit = await first.exitCode;

    expect(expired.exitCode, 75, reason: expired.stderr);
    expect(expired.stderr, contains('timed out'));
    expect(firstExit, 0);
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('lock blocks another process until released', () async {
    final path = uniqueLockPath();
    cleanupLock(path);

    final lock = acquireCheckoutLock(
      path: path,
      timeout: const Duration(seconds: 10),
    );

    final busy = await runLock([
      '--lock-path=$path',
      '--timeout=1',
      '--',
      'true',
    ]);
    expect(busy.exitCode, isNot(0));

    lock.release();

    final free = await runLock(['--lock-path=$path', '--', 'true']);
    expect(free.exitCode, 0);
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('rejects bad usage', () async {
    for (final args in [
      ['--bogus'],
      ['--timeout=x'],
      ['--'],
    ]) {
      final result = await runLock(args);
      expect(result.exitCode, 2, reason: 'usage error expected for $args');
      expect(result.stderr, contains('usage'), reason: 'args: $args');
    }
  }, timeout: const Timeout(Duration(minutes: 1)));
}
