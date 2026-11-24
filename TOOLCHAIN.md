# Toolchain

How to set up and use the local development toolchain for Murdoku. See
[AGENTS.md](AGENTS.md) for build/test commands and guardrails, and
[docs/git-workflow.md](docs/git-workflow.md) for branch/commit rules.

## Flutter

- **Flutter stable channel, Dart bundled with it.** The repo was scaffolded
  against Flutter 3.50.0 / Dart 3.14.0; any recent stable works. Check with
  `flutter doctor -v`.
- **Swift Package Manager is disabled machine-globally**
  (`flutter config --no-enable-swift-package-manager`). The committed iOS
  native integration is CocoaPods (`ios/Podfile` + `ios/Podfile.lock`).
  Flutter prints a notice that SPM will eventually be required again; until
  Flutter drops CocoaPods support, keep the current flow. Do not commit
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
- **CocoaPods**: `brew install cocoapods` (verify with `pod --version`).
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
- Podfile/Podfile.lock were generated and are committed; pod resolution runs
  automatically during the first build (requires `flutter pub get` first).
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

- Commit `ios/Podfile` and `ios/Podfile.lock`. To regenerate locally:
  `flutter pub get && flutter build ios --simulator`.
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
  — the working tree must stay clean afterwards. If a Flutter upgrade changes
  `macos/Podfile.lock`, commit the updated lock (same rule as
  `ios/Podfile.lock`).
- `macos/Flutter/ephemeral/` and `macos/Pods/` are machine-local and stay
  gitignored; never commit a `DEVELOPMENT_TEAM` entry (`grep -r
  DEVELOPMENT_TEAM macos/` must stay empty).
