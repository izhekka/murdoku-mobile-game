# Toolchain

How to set up and use the local development toolchain for Murdoku. See
[AGENTS.md](AGENTS.md) for build/test commands and guardrails, and
[docs/git-workflow.md](docs/git-workflow.md) for branch/commit rules.

## Flutter

- **Flutter stable channel, Dart bundled with it.** The repo was scaffolded
  against Flutter 3.50.0 / Dart 3.14.0; any recent stable works. Check with
  `flutter doctor -v`.
- **Swift Package Manager is the active dependency manager for iOS**
  (re-enabled machine-globally via `flutter config --enable-swift-package-manager`,
  issue #52). The Flutter tool generates
  `ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage` with all iOS
  plugins and the Flutter framework; `flutter build ios` resolves them through Xcode's
  SPM integration. The CocoaPods flow is deprecated: Flutter's tool announces that SPM
  "will be required in a future version of Flutter", and the repo migrated off the
  hybrid SPM/pods pbxproj state before that lands. CocoaPods remains installed only
  because the tool still runs its (now no-op) `pod install` while a Podfile exists —
  see the retention rationale under "Native config rules". Do not commit
  `ios/Flutter/ephemeral/` artifacts (already gitignored).
- The first run of any `flutter` command shows an analytics/telemetry notice
  (tool-level, not part of the app — the app itself is fully offline). Opt out
  with `flutter --disable-analytics` if desired.

## iOS

### Prerequisites (one-time per machine)

- **Xcode** installed and selected: `xcode-select -p` must point at
  `/Applications/Xcode.app/Contents/Developer`; otherwise
  `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.
- **First-launch components**: `xcodebuild -checkFirstLaunchStatus` should
  exit 0; if not, run `sudo xcodebuild -runFirstLaunch` once (this also makes
  the `iphoneos`/`iphonesimulator` SDKs available).
- **CocoaPods**: `brew install cocoapods` (verify with `pod --version`). Still required:
  while the retained `ios/Podfile` exists, the tool runs a (no-op, integration-free)
  `pod install` on every iOS build, which fails without CocoaPods.
- **iOS simulator runtime** (needed to *boot* a simulator, not to build):
  `xcodebuild -downloadPlatform iOS` — one-time, per machine. Without a
  runtime, `flutter build ios --simulator` still succeeds; `xcrun simctl boot`
  does not (no devices listed by `xcrun simctl list devices available`).

### Simulator workflow

```bash
flutter build ios --simulator     # → build/ios/iphonesimulator/Runner.app
xcrun simctl list devices available
xcrun simctl boot <udid>
xcrun simctl install <udid> build/ios/iphonesimulator/Runner.app
xcrun simctl launch <udid> com.murdoku.game
xcrun simctl io <udid> screenshot /tmp/murdoku.png   # launch evidence
```

- Known non-bug: in debug, starting a case blocks the main thread ~60–90 s —
  wait for the home screen / next screen, don't "fix".
- Podfile/Podfile.lock are committed and inert (see "Native config rules"); pod
  resolution runs as a no-op during builds (requires `flutter pub get` first).
- **Verified 2026-11-24 (issue #52):** pure-SPM migration — `flutter build ios
  --simulator` and `flutter build ios --no-codesign` exit 0 with
  `git status --porcelain` clean after the builds; from a cleaned tree
  (`flutter clean`, `ios/Pods` removed) `flutter build ios --config-only
  --no-codesign` exits 0, runs the no-op `pod install`, and leaves the tracked
  tree untouched. `flutter build ios --simulator` after that clean also exits 0
  (SPM resolution from cold works; the #34-era
  "Xcode failed to resolve Swift Package Manager dependencies" failure does not
  recur once the flag is on and the generated package carries the
  FlutterFramework dependency).
- **Verified 2026-11-24 (issue #50):** the flow above works end-to-end —
  install → launch `com.murdoku.game` (pid 19328) → screenshot, each step
  exiting 0 with the home screen visible, on an iPhone 18 Pro simulator
  (UDID `977BB118-A833-4386-B368-C2F09709F72C`, iOS 27.2 runtime, app booted
  with no extra flags). Screenshot evidence is kept locally at
  `docs/superpowers/plans/2026-11-24-ios-sim-launch-evidence/launch-evidence.png`
  (gitignored — binary evidence is not committed).

### Physical device (one-time manual signing; team-agnostic)

Any Apple ID works; the repo must never record a specific team:

1. Open `ios/Runner.xcworkspace` in Xcode.
2. Select the **Runner** target → **Signing & Capabilities** → under Team pick
   your **personal Apple ID team** (Xcode prompts to sign in if needed).
3. On the phone, trust the developer profile: Settings → General → VPN & Device
   Management → trust the profile that appears.
4. Build and run: `flutter run -d <device>` (find the device id with
   `flutter devices`). A team-free compile check is
   `flutter build ios --no-codesign`.
5. **Free Apple ID teams expire every 7 days.** When the device shows a
   provisioning error, re-select the team in Xcode and re-trust the profile.

### Native config rules

- **CocoaPods scaffolding is committed but inert.** `ios/Podfile` declares no
  pods and sets `install! 'cocoapods', :integrate_targets => false`; `ios/Podfile.lock`
  is the regenerated empty lock. This retains the working CocoaPods fallback from
  issue #34 without letting `pod install` re-hybridize the project: CocoaPods
  re-integrates `Pods_` wiring into `Runner.xcodeproj` on every plain install, but
  with no pod declarations and user-project integration disabled, `pod install` (which
  the tool still runs while a Podfile exists) writes only lockfiles. The guard test
  `test/tool/ios_toolchain_guard_test.dart` pins this state.
- The two `#include? "Pods/Target Support Files/…"` lines in
  `ios/Flutter/{Debug,Release}.xcconfig` are tool-managed: the tool re-adds them
  whenever a Podfile and Podfile.lock exist, so removing them churns the tree on every
  build. They are optional includes and resolve nothing while no pods targets are
  generated.
- Expected tool warning on every iOS build while the fallback Podfile exists:
  "All plugins found for ios are Swift Packages, but your project still has CocoaPods
  integration…". It is benign (retention is deliberate; see the banner in
  `ios/Podfile`), and it disappears if the Podfile is ever removed.
- **Restoring CocoaPods** (e.g. a plugin without `Package.swift` support): restore the
  podhelper target block from commit 43ab35a, run
  `flutter config --disable-swift-package-manager`, then `flutter build ios` and commit
  the regenerated `Podfile.lock`.
- `flutter build ios` (device, signed) requires a code-signing identity on the machine
  and exits early without one; `flutter build ios --config-only` inherits the same
  check. The verified device-path check on machines without certificates is
  `flutter build ios --config-only --no-codesign` (exit 0, issue #52).
- **Never commit a `DEVELOPMENT_TEAM` entry** — `grep -r DEVELOPMENT_TEAM ios/`
  must stay empty (signing is a local Xcode setting, not a repo one).
- `ios/Flutter/Generated.xcconfig`, `ios/Pods/`, and
  `ios/Flutter/ephemeral/` are machine-local and stay gitignored.
- Bundle id `com.murdoku.game` stands until the Task 17 rename guardrail.

## macOS

- The CocoaPods scaffolding is committed: `macos/Podfile` +
  `macos/Podfile.lock`, the `#include? "Pods/Target Support Files/..."`
  lines in `macos/Flutter/Flutter-{Debug,Release}.xcconfig`, and the Pods
  wiring in `macos/Runner.xcodeproj` + `macos/Runner.xcworkspace`.
  Every flutter command (even iOS builds/tests) regenerates this
  scaffolding, so committing it — done once via `flutter build macos
  --debug` — makes regeneration a no-op and kills the phantom worktree
  diff (issue #51).
- To regenerate locally: `flutter pub get && flutter build macos --debug`
  — the working tree must stay clean afterwards. With the SPM feature flag on
  (issue #52, iOS), the first macOS build after this migration is expected to
  regenerate `macos/Podfile.lock` without `shared_preferences_foundation`
  (the plugin ships `Package.swift`, so SPM is expected to serve it there
  too) — verify at that build and commit the updated lock (same rule as
  `ios/Podfile.lock`; this forecast is unverified — no macOS build has run
  since the flag change). The macOS pbxproj already carries its
  `FlutterGeneratedPluginSwiftPackage` references and the macOS scheme its
  `macos_assemble.sh prepare` pre-action, so no macOS pbxproj/scheme migration
  is expected.
- `macos/Flutter/ephemeral/` and `macos/Pods/` are machine-local and stay
  gitignored; never commit a `DEVELOPMENT_TEAM` entry (`grep -r
  DEVELOPMENT_TEAM macos/` must stay empty).
