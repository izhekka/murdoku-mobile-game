# Code guidelines

Conventions for Murdoku contributors — human or agent. This is the document the
machine-enforced rules map into: every lint in `analysis_options.yaml`'s
curated set (issue #33, decision record [0006](spec/0006-quality-gates.md)) has
a row in the mapping table at the bottom pointing at the section that explains
the rule. The grounding is the
[Effective Dart](https://dart.dev/effective-dart) style guide; this file only
adds what is Murdoku-specific or worth restating for enforcement.

## 1. SOLID in Flutter/Riverpod idioms

SOLID is applied the Flutter way, not as Java ceremony:

- **Single Responsibility** — one widget = one thing on screen; one provider /
  controller = one state concern. `lib/` is split accordingly: domain logic
  (`lib/domain/`), state controllers (`lib/state/`), persistence
  (`lib/storage/`), screens and widgets (`lib/ui/`), cross-cutting helpers
  (`lib/core/`). A widget builds UI and delegates everything else; a
  controller owns state transitions and never touches widgets.
- **Open/Closed** — extend behavior through new implementations (new skins,
  new clue kinds, new tool modes), not by editing and re-testing verified
  solver/generator code.
- **Liskov Substitution** — skins (`SkinTokens` implementations) and settings
  enums are interchangeable without surprising call sites; a new skin must
  satisfy exactly the token contract.
- **Interface Segregation** — keep constructors and provider interfaces
  minimal; do not pass whole controllers where a single callback or value
  suffices.
- **Dependency Inversion** — widgets depend on Riverpod providers, never on
  concrete storage. `lib/state/providers.dart` is the seam: controllers get
  repositories and clocks via provider overrides, which is what makes
  `SharedPreferences` and time injectable in tests. No service-locator
  globals, no singletons with mutable static state.

## 2. Naming and file/folder conventions

- Files and directories: `snake_case`; one primary class per file where
  practical, filename mirrors the class (`game_controller.dart`).
- Types: `PascalCase`. Members, variables, parameters: `camelCase`.
  Constants: `camelCase` (Dart convention), or `SCREAMING_CASE` for
  file-local sentinels.
- Private members start with `_`. Widget callbacks are named for what happened
  (`onPressed`, `onCellTap`), not how they act.
- The package import prefix is `package:murdoku/...` — see the import rules
  below.
- New feature areas follow the existing layout
  (`core/`, `domain/`, `state/`, `storage/`, `ui/screens/`, `ui/widgets/`,
  `l10n/`); domain rules live in `lib/domain/`, never in widgets.

## 3. Imports, directives, and comments

- **Always package imports** for anything under `lib/` — relative
  `../../state/x.dart` chains rot during moves; `package:murdoku/state/x.dart`
  is stable. Files outside `lib/` (e.g. `test/` importing `tool/`) keep
  relative imports because package URIs cannot address them.
- **Directive order**: `dart:` first, then `package:`, then relative;
  alphabetical within each section (`directives_ordering`).
- **Doc comments** attach to a declaration and start with a sentence; a
  dangling `///` block before `library;`-less file tops is flagged. Keep
  `library;` as the first directive when the file header has a `///` comment.
- **TODOs** follow Flutter style: `// TODO(username): message` with an owner —
  unowned TODOs rot.
- Quotes are single; use doubles only when the string itself contains a
  single quote.

## 4. Types and dynamism

- Declare return types on every function and method — inference hides
  contract changes.
- Do not stringify types (`Type.toString`, `runtimeType` in logic); switch on
  explicit values or sealed hierarchies instead. Runtime type strings break
  under minification and tree-shaking.
- Prefer exact types over `dynamic`; parse boundaries convert to typed models
  immediately (see §7).
- Do not pass redundant arguments: if a value equals the parameter's default,
  omit it — a redundant argument lies about intent (readers assume the
  explicit value differs from the default).
- Constructor parameters that are unused are dead weight; drop them.

## 5. Async discipline

- Never drop a `Future`: `await` it, or hand it to `unawaited(...)` when
  fire-and-forget is intended. Silent futures swallow errors.
- Do not use blocking-I/O helpers (`File.exists`/`existsSync` style calls in
  async contexts) — use the async variants (`File.exists()` style) inside
  async code.
- `StreamSubscription`s must be `cancel()`ed (widget `dispose`, controller
  teardown); sink owners must `close()` them. Leaked subscriptions keep
  controllers and timers alive after the widget dies.
- Return `Future<void>` from async functions; never `return null` from a
  `Future`-typed path — throw or return a typed result.

## 6. Errors and control flow

- **Throw only `Error`/`Exception` subtypes** (or objects implementing them);
  never `throw 'string'` or arbitrary objects.
- **Catch clauses carry an `on` type**. Feature code catches the specific
  failure it can handle (`on FormatException`, `on TypeError`). Last-resort
  persistence guards around stored-JSON parsing may use `on Object catch (e)`
  — the honest spelling of "any failure of corrupt stored data" — and must
  degrade to a safe default (see `PrefsRepository`), never swallow silently:
  log via `debugPrint` and return the default value.
- Catch blocks either handle the failure or rethrow; never write an empty
  catch.

## 7. Immutability and JSON (no codegen)

- Model classes are immutable: `final` fields, `const` constructors where
  possible, `==`/`hashCode` overridden (or sealed enums for fixed sets).
  State objects expose `copyWith` instead of setters.
- **JSON is hand-written**: every model that persists implements `toJson` /
  `fromJson` by hand — no `build_runner`, `freezed`, or `json_serializable`
  (project guardrail). `fromJson` validates via typed casts
  (`as String? ?? fallback`) and is defensive: corrupt persisted data degrades
  to defaults through the storage guards in §6, it does not crash the app.
- Parsing lives next to the model (`fromJson` static or factory), not at the
  call site.

## 8. Localization (hard rule)

Every user-facing string goes through `AppLocalizations` (arb files under
`lib/l10n/`); `lib/l10n/generated/` is generated output and never edited by
hand. Widget tests fetch strings through the same delegates they pump. No
hardcoded English or Russian literals in widget code — including sheet titles,
buttons, and accessibility labels.

## 9. Formatting and layout

`dart format` is the single formatter; CI and the pre-commit hook run
`dart format --output=none --set-exit-if-changed` and reject unformatted
code. Trailing commas are required on multi-line argument lists
(`require_trailing_commas`) — they keep diffs minimal and make `dart format`
stable. Do not fight the formatter.

## 10. Complexity vs coverage (CRAP gate)

`tool/crap_check.dart` computes per-method CRAP
(`comp² × (1−cov)³ + comp`) from AST complexity and `flutter test --coverage`
data; threshold 5. Every measured member in `lib/**` must stay at or below
the threshold — since issue 35 burned the baseline to zero, the committed
baseline file is gone and the gate runs hard: any over-threshold member fails
CI and `make quality`. Fix by splitting the method or covering it.
`--update-baseline` can still write a local ratchet file for experimental
work, but no baseline is committed. Coverage collection itself excludes
`lib/l10n` (issue 37): before the gate reads the report,
`tool/coverage_filter.dart` drops every generated-localization lcov section
(`flutter test --coverage` cannot filter paths, and hit counts there jitter
between runs of identical code).

## 11. Widget-test flake diagnostics (pump budgets vs real timers)

How to diagnose a flake of the discard-then-start class
(`test/ui/screens/home_screen_test.dart`, made deterministic in issue 32).
The historical flake was never reproduced — 8 pre-fix and 13 post-fix
full-suite runs were green — so the diagnosis below is analytic; treat this
section as the source of truth for the failure mode.

- **Fake-time pump budgets vs real timers.** `tester.pump(...)` advances the
  fake clock, and a real `Timer` scheduled by a pumped widget — e.g.
  GameScreen's 1-second tick timer — fires the moment accumulated fake time
  reaches its due time. A flow whose fake time can drift across that due time
  (unbounded `pumpAndSettle` chains, or per-step settle budgets that
  accumulate without a ceiling) is nondeterministic: the timer can fire
  between pumps, throwing "A Timer is still pending …" in teardown or
  desynchronizing the flow. The repo's fix pattern (issue 32) is fixed,
  bounded pump budgets, one per frame-dispatch step, whose post-mount flow
  total stays ≥ 600 ms below the first fire of GameScreen's 1-second tick
  timer — exact regardless of scheduler state. Prefer that pattern over
  `pumpAndSettle` wherever timers or post-frame callbacks schedule frames.
- **Masked teardown error.** When the test body throws (an assertion fails)
  *before* teardown, flutter_test skips tree cleanup in `_runTestBody`, and
  `postTest` then reports:

  > A Timer is still pending even after the widget tree was disposed
  > (binding.dart:2657)

  That pending-timer error *masks the real error*: the reported failure is
  the undisposed timer, not the body assertion that aborted the flow before
  cleanup could run.
- **On a recurrence, capture the FULL failure log.** Only a full log
  distinguishes a body-assertion failure from the masking path: scan the
  entire output for an exception before teardown, and treat a bare
  "Timer is still pending" as the primary failure only when no earlier body
  exception appears anywhere in the log. Never chase the teardown error past
  a body failure — diagnose from the first error in the log.

## 12. Concurrent suite runs on one checkout (issue 43)

Two overlapping `flutter test` invocations on the same working copy race the
shared build directory: one of three parallel full-suite runs during issue 32
died with `PathNotFoundException: Cannot copy file to
…/build/unit_test_assets/NativeAssetsManifest.json` while the other two
passed. Suite runs serialize per checkout instead:

- **Mechanism.** `tool/flutter_test_lock.dart` takes an exclusive advisory
  lock on `<checkout>/.dart_tool/flutter_test.lock` (created on demand) and
  holds it for the lifetime of the guarded command, then forwards the
  command's exit code with inherited stdio. The lock is kernel-managed — it
  is released when the holder process dies, so there is no stale-lock
  takeover path. The lock file itself is never deleted: unlinking it would
  break exclusion for processes still waiting on the old inode. The default
  lock path is anchored on the enclosing checkout (found by walking up to
  the nearest `pubspec.yaml`), so runs started from a subdirectory of the
  checkout also hold the same lock; a run started outside any package tree
  has no checkout root and must pass `--lock-path`.
- **How to invoke.** `make quality` wraps its whole coverage pipeline
  (`flutter test --coverage` → `tool/coverage_filter.dart` →
  `tool/crap_check.dart`) in the lock, because an overlapping run must not
  interleave coverage writes with a waiting run's filter/crap reads either.
  Directly: `dart run tool/flutter_test_lock.dart -- flutter test <args>`
  (flags: `--timeout=<seconds>`, default 900; `--lock-path=<path>`; exit
  codes 2 = usage error, 75 = timed out waiting for the lock, 1 = the guarded
  command failed, 127 = command not found).
- **Constraint.** A bare `flutter test` bypasses the lock entirely. When
  runs can overlap on one checkout, start them through `make quality` or the
  lock tool. CI runs its steps sequentially and needs no lock; parallel runs
  on *different* checkouts use different lock files and do not block each
  other.
- **Caveats.** The kernel releases the lock on holder death, but nothing
  protects against *recreating* the lock file mid-run: never `flutter clean`
  or wipe `.dart_tool` while a locked run is active (a recreated lock is a
  new inode and a waiter would race the holder). The lock is per-process
  POSIX record lock — a second acquire in the same process succeeds
  immediately. One residual window: if the wrapper itself is killed while
  its guarded child keeps running, the orphaned child holds no lock and the
  next acquisition races it — kill the whole process group (a terminal
  Ctrl-C already does), not just the wrapper.
- **Reservation.** The guarantee assumes a local checkout on a filesystem
  with advisory locking (macOS/Linux). On mounts without it, the lock
  silently degrades to a no-op and the build-dir race returns.
- **Re-proof.** Two overlapping runs must both exit 0 without a
  `PathNotFoundException`; the second acquires the lock only after the first
  released it:

  ```sh
  (dart run tool/flutter_test_lock.dart -- flutter test --coverage \
     > /tmp/lock_demo_a.log 2>&1; echo "A exit $?") &
  (dart run tool/flutter_test_lock.dart -- flutter test --coverage \
     > /tmp/lock_demo_b.log 2>&1; echo "B exit $?") &
  wait
  grep -c PathNotFoundException /tmp/lock_demo_a.log /tmp/lock_demo_b.log
  ```

## 13. Generator attempt-seed derivation (issues 46/61)

`generateCase` tries 40 attempts per widening window and stores the first
successful attempt seed. Under issue 46 every attempt reused the raw
`requested + i`, so requested seeds inside one failure basin collapsed onto
one stored seed and returned the **identical case** — measured 2026-11-24:
easy 1–4 → 5, 15–19 → 20; standard 1–4 → 5, 28–43 → 44; hard 1–5 → 6,
26–44 → 45. Issue 46 pinned that surface by test; issue 61 removed it.

- **Removed, not re-pinned.** Issue 61 re-derives each attempt's rng seed
  from `(requested seed, attempt index)` — a splitmix64 stream step
  (advance by the golden-ratio constant per attempt) followed by the
  splitmix64 finalizer, masked to 31 bits
  (`_derivedSeed` in `case_factory.dart`). Nearby requested seeds walk
  decorrelated attempt streams, so adjacent seeds return distinct cases;
  the basins above are gone. `dailySeedFor` derivation is untouched, but
  consecutive dates now generate distinct cases too (the
  `standard/20261119`/`standard/20261120` golden digests differ since the
  remap), still deterministic per date.
- **What still fails is budget exhaust, not convergence.** Exhausts were
  re-scanned after the remap (measured 2026-11-24): easy 0/20000, standard
  5/20000 (0.025%), hard 368/12000 (≈3.1%, chunked windows over seeds
  9001..21000) — stable per window, and the failures are decorrelated
  singles instead of the old contiguous always-fail bands (the pre-#61
  81-seed band at 42848100 is history). The runtime-drawn path routes
  through `generateCaseWithRecovery` (issue 45) — 9 windows of 40 derived
  attempts in total, the exhausted seam plus 8 fresh strides (360
  attempts) — and its measured seams are
  re-pinned: hard 111 (single exhausted window), hard 375 → 415 → 455
  (two-window corridor), and the daily date-seed 2031-09-28 (the issue-60
  corridor 2055-12-25 now generates directly).
- **Why issue 46 originally froze this (history).** The pinned golden
  digests hash `toJson()`, which includes each attempt's stored seed, so
  any attempt-seed remap drifts them (easy/1 → attempt 5, standard/1 → 5,
  hard/1 → 6 pre-remap). Delivering the variety therefore required one
  coordinated change — re-measure the mapping, regenerate the golden
  digests, re-pin the corridors — which is exactly what issue 61 landed
  (hard/111 exhausts under the derived mapping, so that golden slot moved
  to the generating neighbor 112).
- **Consciously updating the pin.** Re-measure first with a temporary
  probe that prints requested → stored seeds across difficulties × seeds
  (never hand-write the table; a tracked probe tool is open issue #62),
  then update the convergence table together with the golden digests and
  every measured corridor seam in the same change, stating the cause, and
  mutation-verify the pin's teeth (reverting the derivation — or shifting
  any stream constant — must fail the pins).

## Enforced lint → guideline mapping

| Lint rule | Guideline section |
|-----------|-------------------|
| `always_declare_return_types` | §4 Types and dynamism |
| `use_super_parameters` | §4 Types and dynamism |
| `prefer_final_in_for_each` | §4 Types and dynamism |
| `always_use_package_imports` | §3 Imports, directives, and comments |
| `directives_ordering` | §3 Imports, directives, and comments |
| `dangling_library_doc_comments` | §3 Imports, directives, and comments |
| `flutter_style_todos` | §3 Imports, directives, and comments |
| `prefer_single_quotes` | §3 Imports, directives, and comments |
| `avoid_type_to_string` | §4 Types and dynamism |
| `avoid_redundant_argument_values` | §4 Types and dynamism |
| `avoid_unused_constructor_parameters` | §4 Types and dynamism |
| `avoid_slow_async_io` | §5 Async discipline |
| `unawaited_futures` | §5 Async discipline |
| `cancel_subscriptions` | §5 Async discipline |
| `close_sinks` | §5 Async discipline |
| `avoid_catches_without_on_clauses` | §6 Errors and control flow |
| `only_throw_errors` | §6 Errors and control flow |
| `no_adjacent_strings_in_list` | §3 Imports, directives, and comments (list literals stay itemized) |
| `require_trailing_commas` | §9 Formatting and layout |
| `unnecessary_lambdas` | §2 Naming and file/folder conventions (prefer tear-offs) |
| `unnecessary_parenthesis` | §9 Formatting and layout |
| `unnecessary_statements` | §6 Errors and control flow (no dead expression statements) |
