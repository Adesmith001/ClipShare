# ClipShare 0.2.0 beta testing

Candidate version: `0.2.0+9`. Updated: 18 November 2026.

## Implemented scope

- Local folder create/rename/remove, move and Unfiled views; folders survive app relaunch and download replacement.
- Combined source/title/path search, folder and media filters.
- Selection and serial batch move, delete, retry/start, cancellation, and Photos/Gallery export with eligibility and result counts.
- Confirmed local deletion that preserves exported copies, local storage display, Help and sanitized diagnostic copying.
- Supported social-share intake, pending deduplication, individual corrupted-record isolation/recovery, native safe failure states and transfer reconciliation.
- iPhone authenticated Instagram WebKit page parsing/queueing without cookie extraction. This implementation still requires signed-device sign-in and session verification.
- Custom code-drawn ClipShare launcher mark and configurable Android release signing without debug fallback.
- CI gates formatting, analyze, Flutter tests, Android debug/native-test compilation, iOS app/extension compilation and native simulator tests before signed export.

## What has and has not been verified locally

The development host is Windows. Flutter tests can exercise real filter logic and widgets with mocked native channels, and Android Kotlin/APK compilation can run. There is no connected Android device/configured emulator, and no Apple toolchain on this host. Native device tests, macOS CI and signed iPhone flows remain unverified until run in those environments. Do not treat the fixture parser tests as proof of live-provider availability.

## Recorded local results

On 18 November 2026, after the final Flutter/Android integration:

| Check | Result |
| --- | --- |
| Dart formatting check | Passed, 9 files, no changes required |
| Flutter analyzer | Passed, no issues |
| Flutter tests | Passed, 30 tests |
| Android debug APK | Built successfully, version `0.2.0+9` |
| Android app + instrumentation Kotlin compilation | Passed; six native instrumentation test methods compile |
| Native Android device tests | Not run; no connected device/emulator |
| iOS source spec and quality reviews | Completed; findings fixed; ten XCTest methods added |
| Apple build, XCTest runtime, and signed iPhone flows | Not run; Apple toolchain/device unavailable on this Windows host |
| Workflow YAML/plist/scheme parsing, icon dimensions, APK version | Validated |

The local debug APK is `build/app/outputs/flutter-apk/app-debug.apk`. It is a debug verification build; a distributed release candidate still needs owner-supplied signing credentials. The workflow runs on main pushes and pull requests. Check GitHub Actions for the exact candidate commit; local verification does not establish remote CI success.

## Automated checks

```sh
flutter pub get --enforce-lockfile
# Check formatting without rewriting:
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --debug --no-pub
```

Android native tests compile with `./gradlew :app:compileDebugAndroidTestKotlin` from `android/` (use `gradlew.bat` on Windows). With an Android device/emulator attached, run `./gradlew :app:connectedDebugAndroidTest`. The instrumentation tests use isolated test metadata and do not need live social-provider requests.

On macOS, the workflow builds the unsigned device app/extension and runs `RunnerTests` using the Runner scheme in an available iPhone simulator. To run manually after `flutter build ios --simulator --debug --no-pub`:

```sh
xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner \
  -configuration Debug -destination 'platform=iOS Simulator,name=YOUR_INSTALLED_IPHONE_SIMULATOR' \
  CODE_SIGNING_ALLOWED=NO
```

Use an installed simulator name or UDID. Signed share-sheet testing must use the real app/extension App Group provisioning profiles described in README.

## Candidate acceptance checklist

All rows below are device checks, pending until recorded by a tester. Record platform, OS, build, link/provider (share only content you want included in a report), expected result, and actual outcome.

- [ ] Upgrade from `0.1.6+8` without losing existing downloads or playback.
- [ ] Download a direct MP4 with audio; JPEG, PNG and WebP. Preview/play and export each, then relaunch and repeat.
- [ ] Feed an HTML error page at a media URL and corrupt data; show failure, never false Saved.
- [ ] Paste and share an actual X, Pinterest/pin.it, Instagram, and YouTube supported post through each advertised platform intake path.
- [ ] Share into a closed app and an already-open app; resume and start the pending item.
- [ ] Share/paste equivalent tracked/short/canonical URLs repeatedly; no dead pending duplicates.
- [ ] On signed iPhone: first Instagram login resumes the original post; a later share reuses session; Reel/photo/mixed carousel queue in original order; disconnect and reauthenticate.
- [ ] Private/deleted/restricted post, login challenge, offline connection and timeout each produce a useful status with a recovery route.
- [ ] Partial carousel: successful slides stay present, missing supported slides retry without duplicating saved media.
- [ ] Lock screen, background app, interrupt network, relaunch and force-close during transfers; verify continuing or explicitly retryable states.
- [ ] Cancel and retry a transfer, including after relaunch and from extension-created downloads; no resurrected deleted entry.
- [ ] Remove pending/failed/saved/active entries; local files are freed and exported copies remain intact.
- [ ] Decline Photos access or cancel Files export; local file remains available for another export.
- [ ] Create, rename and remove folders; move individual/batch items; retry an item and verify its folder; relaunch and verify persistence.
- [ ] Search by multiple words, source, and path while changing media/folder filters; clearing filters restores the library.
- [ ] Select visible results, change filters and verify selected count; batch move/delete/retry/cancel/export; ineligible items skipped; failure of one item does not stop later eligible items.
- [ ] Low storage, one unreadable queue record, missing local file; healthy files remain accessible and failures explain recovery.
- [ ] Populate a realistic library, start another download, and check scrolling/refresh responsiveness.
- [ ] Small phone, landscape, large text, keyboard, VoiceOver/TalkBack; all actions reachable and labelled.
- [ ] Copy diagnostic report; verify version/build/OS and error codes are included, while URLs/tokens/titles/folder names/sessions are excluded.

## Distribution prerequisites

- Android release key configured locally or in CI; retain the same signing identity for future upgrades. No key was created by this change.
- iOS owner-supplied certificate and App Group-enabled Runner/ShareExtension profiles, registered devices for the current development IPA route, and a private repository for signed artifacts.
- Run the checks on the exact candidate commit. Signed export remains explicitly dispatched on main; no build was uploaded or distributed by the implementation task.
