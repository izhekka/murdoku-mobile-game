/// Per-checkout lock that serializes overlapping suite runs on one working
/// copy (issue 43): two concurrent `flutter test` invocations race the shared
/// `build/unit_test_assets` directory, producing false failures like
/// `PathNotFoundException: Cannot copy file to
/// …/build/unit_test_assets/NativeAssetsManifest.json`.
///
/// The CLI takes an exclusive advisory lock on
/// `<checkout>/.dart_tool/flutter_test.lock` (created on demand) and keeps it
/// for the lifetime of the guarded command:
///
/// ```
/// dart run tool/flutter_test_lock.dart [--timeout=<seconds>] [--lock-path=<path>] [-- <command...>]
/// ```
///
/// Without `--`, the guarded command defaults to `flutter test`. The child's
/// stdout/stderr are inherited and its exit code is forwarded. Exit codes:
/// 2 = usage error, 75 = timed out waiting for the lock (EX_TEMPFAIL, so a
/// caller can tell "never ran" apart from "ran and failed", whose code is the
/// forwarded child code), 127 = command not found. The lock is kernel-managed:
/// it is released when the holder process dies, so there is no stale-lock
/// takeover path. The lock file itself is deliberately never deleted —
/// unlinking it would break exclusion for processes still waiting on the old
/// inode (for the same reason, do NOT run `flutter clean` / recreate
/// `.dart_tool` while a locked run is active — the recreated lock is a new
/// inode and a waiter would race the holder).
///
/// Known residual window: if the wrapper process is killed outright (SIGKILL,
/// or an exit path that leaves the child alive) while the guarded command is
/// still running, the kernel frees the lock immediately and the next
/// acquisition races the orphaned child. Kill the whole process group
/// (a terminal Ctrl-C already does) rather than only the wrapper.
///
/// A bare `flutter test` bypasses this lock entirely; when runs can overlap,
/// invoke the suite through `make quality` (which wraps its coverage pipeline
/// here) or through this tool directly.
library;

import 'dart:io';

const Duration _pollInterval = Duration(milliseconds: 200);
const int _defaultTimeoutSecs = 900;

/// Walks up from [start] (default: the working directory) until a
/// `pubspec.yaml` marks the enclosing package/checkout root; null when the
/// chain reaches the filesystem root without one (the caller must refuse to
/// lock rather than share a machine-global file or crash on an unwritable
/// root). Anchoring on the checkout rather than [Directory.current] keeps
/// every run started anywhere inside one checkout on the same lock file.
Directory? findCheckoutRoot({Directory? start}) {
  var dir = start ?? Directory.current;
  while (true) {
    final marker = File('${dir.path}${Platform.pathSeparator}pubspec.yaml');
    if (marker.existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      return null;
    }
    dir = parent;
  }
}

/// Default lock location: `<checkout>/.dart_tool/flutter_test.lock`, anchored
/// on the enclosing checkout (see [findCheckoutRoot]); null outside any
/// package tree, where the caller has no sensible default lock file.
String? defaultLockPath() {
  final root = findCheckoutRoot()?.path;
  if (root == null) {
    return null;
  }
  return '$root${Platform.pathSeparator}.dart_tool'
      '${Platform.pathSeparator}flutter_test.lock';
}

/// A held lock on the checkout test lock file.
class CheckoutLock {
  final RandomAccessFile _raf;

  CheckoutLock._(this._raf);

  /// Closes the underlying descriptor; the kernel drops the advisory lock.
  /// The lock file is left in place on purpose (see the library docs).
  void release() {
    _raf.closeSync();
  }
}

/// Thrown when the lock at [CheckoutLockTimeoutException.path] could not be
/// acquired within [CheckoutLockTimeoutException.timeout].
class CheckoutLockTimeoutException implements Exception {
  final String path;
  final Duration timeout;

  CheckoutLockTimeoutException({required this.path, required this.timeout});

  @override
  String toString() =>
      'flutter_test_lock: timed out after ${timeout.inSeconds}s waiting for '
      'the checkout test lock at $path; another suite run appears active in '
      'this checkout';
}

/// Acquires the exclusive lock at [path], polling until it is held or
/// [timeout] elapses. [onWait] fires once when the first attempt finds the
/// lock busy.
///
/// The lock is advisory and cross-process: another process locking the same
/// file blocks this call (and vice versa). It is released when the returned
/// [CheckoutLock] is released, or whenever the holder process dies. One lock
/// per process: POSIX record locks are not reentrant, so a second
/// [acquireCheckoutLock] call in the same process succeeds immediately
/// instead of blocking, and closing *either* descriptor drops the exclusion
/// for both.
CheckoutLock acquireCheckoutLock({
  required String path,
  required Duration timeout,
  void Function(Duration waited)? onWait,
}) {
  File(path).parent.createSync(recursive: true);
  final raf = File(path).openSync(mode: FileMode.append);
  // Monotonic deadline: a wall clock can step underneath a long wait (NTP).
  final watch = Stopwatch()..start();
  var waited = Duration.zero;
  while (true) {
    try {
      // lockSync's default mode is FileLock.exclusive, which is non-blocking:
      // it throws FileSystemException instead of waiting when another process
      // holds the lock, which is exactly the polling behavior wanted here.
      raf.lockSync();
      return CheckoutLock._(raf);
    } on FileSystemException {
      if (watch.elapsed > timeout) {
        raf.closeSync();
        throw CheckoutLockTimeoutException(path: path, timeout: timeout);
      }
      if (onWait != null && waited == Duration.zero) {
        onWait(waited);
      }
      sleep(_pollInterval);
      waited += _pollInterval;
    }
  }
}

Future<void> main(List<String> args) async {
  var timeout = const Duration(seconds: _defaultTimeoutSecs);
  String? lockPath;
  List<String>? command;
  var usageError = false;

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--') {
      command = args.sublist(i + 1);
      break;
    } else if (arg.startsWith('--timeout=')) {
      final secs = int.tryParse(arg.substring('--timeout='.length));
      if (secs == null || secs.isNegative) {
        usageError = true;
      } else {
        timeout = Duration(seconds: secs);
      }
    } else if (arg.startsWith('--lock-path=')) {
      final value = arg.substring('--lock-path='.length);
      if (value.isEmpty) {
        usageError = true;
      } else {
        lockPath = value;
      }
    } else {
      usageError = true;
    }
  }

  if (usageError || (command != null && command.isEmpty)) {
    stderr.writeln(
      'usage: dart run tool/flutter_test_lock.dart'
      ' [--timeout=<seconds>] [--lock-path=<path>] [-- <command...>]',
    );
    exitCode = 2;
    return;
  }

  final run = command ?? const <String>['flutter', 'test'];
  var path = lockPath;
  if (path == null) {
    path = defaultLockPath();
    if (path == null) {
      stderr.writeln(
        'flutter_test_lock: no pubspec.yaml found up from '
        '${Directory.current.path}; no checkout root to anchor the lock at.'
        ' Pass --lock-path=<path> to pick the lock file explicitly.',
      );
      stderr.writeln(
        'usage: dart run tool/flutter_test_lock.dart'
        ' [--timeout=<seconds>] [--lock-path=<path>] [-- <command...>]',
      );
      exitCode = 2;
      return;
    }
  }

  final CheckoutLock lock;
  try {
    lock = acquireCheckoutLock(
      path: path,
      timeout: timeout,
      onWait: (waited) {
        stderr.writeln(
          'flutter_test_lock: another suite run holds the checkout test lock'
          ' at $path; waiting for it to finish',
        );
      },
    );
  } on CheckoutLockTimeoutException catch (e) {
    stderr.writeln('$e');
    // EX_TEMPFAIL: distinct from the guarded command's own failure so
    // "never ran" is tellable apart from "ran and failed".
    exitCode = 75;
    return;
  }

  try {
    final proc = await Process.start(
      run.first,
      run.sublist(1),
      mode: ProcessStartMode.inheritStdio,
    );
    exitCode = await proc.exitCode;
  } on ProcessException catch (e) {
    stderr.writeln('flutter_test_lock: failed to start command: ${e.message}');
    exitCode = 127;
  } finally {
    lock.release();
  }
}
