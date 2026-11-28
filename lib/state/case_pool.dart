import 'dart:async';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:murdoku/domain/generator/case_factory.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/state/providers.dart';
import 'package:murdoku/storage/prefs_repository.dart';

/// One background refill batch: [count] fresh cases for [difficulty].
/// Implementations log per-case failures and skip them — generation
/// problems never reach the UI (issue 108).
typedef CasePoolBatch = Future<List<CaseData>> Function(
  Difficulty difficulty,
  int count,
);

/// Refill trigger: pools holding fewer cases get one batch of
/// [_batchSize]. Each deficient difficulty gets its own batch.
const int _refillBelow = 5;
const int _batchSize = 10;

/// Production batch seam (issue 108): one [Isolate.run] round per case so
/// generation never runs on the UI isolate. Fresh random seeds; recovery
/// ([generateCaseWithRecovery]) absorbs the rare exhausted seed, and any
/// per-case failure is logged and skipped.
Future<List<CaseData>> isolateBatch(Difficulty difficulty, int count) async {
  final cases = <CaseData>[];
  for (var i = 0; i < count; i++) {
    final seed = Random().nextInt(1 << 30);
    try {
      cases.add(
        await Isolate.run(
          () => generateCaseWithRecovery(difficulty: difficulty, seed: seed),
        ),
      );
    } on Object catch (e) {
      debugPrint('case pool: $difficulty batch case skipped: $e');
    }
  }
  return cases;
}

/// Overridden in tests to stub generation without isolates.
final casePoolBatchProvider = Provider<CasePoolBatch>((ref) => isolateBatch);

/// Three independent per-difficulty pools of pre-generated unstarted cases
/// (issue 108). New cases are served by [CasePoolController.take] (random
/// pop); [CasePoolController.maybeRefill] tops deficient pools up in the
/// background while the app is open. State is the in-memory pool; every
/// mutation persists through [prefsRepositoryProvider].
class CasePoolController extends Notifier<CasePool> {
  /// One in-flight batch per difficulty (single-flight, issue 108).
  final Map<Difficulty, Future<void>> _inFlight = {};

  @override
  CasePool build() => ref.read(prefsRepositoryProvider).loadCasePool();

  /// Random pop of one stored case for [difficulty], persisting the
  /// remainder and checking the refill rule afterwards. Null when the pool
  /// is empty (the caller owns the synchronous fallback), with no refill
  /// check — the fallback start triggers it instead.
  CaseData? take(Difficulty difficulty) {
    final list = _pool(difficulty);
    if (list.isEmpty) return null;
    final picked = list[Random().nextInt(list.length)];
    _replace(difficulty, [...list]..remove(picked));
    unawaited(maybeRefill());
    return picked;
  }

  /// Refill check: every deficient, not-in-flight difficulty starts one
  /// background batch of [_batchSize]. Returns when every observed batch
  /// (started here or already in flight) completed. With the forced-seed
  /// pin (integration tests) the pool is bypassed entirely — no batches.
  Future<void> maybeRefill() {
    if (ref.read(forcedSeedProvider) != null) return Future.value();
    return Future.wait([for (final d in Difficulty.values) _refillLeg(d)]);
  }

  /// The refill leg of one difficulty: joins an in-flight batch, starts
  /// one when the pool is deficient, or completes immediately.
  Future<void> _refillLeg(Difficulty difficulty) {
    final existing = _inFlight[difficulty];
    if (existing != null) return existing;
    if (!_deficient(difficulty)) return Future.value();
    final future = _runBatch(difficulty);
    _inFlight[difficulty] = future;
    return future;
  }

  /// True when the pool holds fewer than [_refillBelow] cases.
  bool _deficient(Difficulty difficulty) =>
      _pool(difficulty).length < _refillBelow;

  Future<void> _runBatch(Difficulty difficulty) async {
    try {
      final cases = await ref.read(casePoolBatchProvider)(
        difficulty,
        _batchSize,
      );
      _replace(difficulty, [..._pool(difficulty), ...cases]);
    } on Object catch (e) {
      debugPrint('case pool: $difficulty refill batch failed: $e');
    } finally {
      // Detach the entry; maybeRefill callers hold the same future.
      _inFlight.remove(difficulty)?.ignore();
    }
  }

  List<CaseData> _pool(Difficulty difficulty) =>
      state.byDifficulty[difficulty] ?? const <CaseData>[];

  void _replace(Difficulty difficulty, List<CaseData> cases) {
    state = CasePool(byDifficulty: {...state.byDifficulty, difficulty: cases});
    unawaited(ref.read(prefsRepositoryProvider).saveCasePool(state));
  }
}

final casePoolControllerProvider =
    NotifierProvider<CasePoolController, CasePool>(CasePoolController.new);
