# ClipShare beta readiness review

Reviewed: 17 November 2026. Version reviewed: `0.1.6+8`.

This is the historical review that prompted the `0.2.0+9` implementation. See [beta testing](beta-testing.md) and the current README for implemented behavior and remaining device verification.

The direct-media download foundation is in place, but the social-sharing experience has functional gaps that should be addressed before a wider beta. A tightly scoped internal test can still focus on direct-media downloads while those gaps are resolved.

This review inspected the Flutter screens and provider parsers, Android sharing/downloads/player, iOS Share Extension/background downloads/export, persistence, tests, and build configuration. Application code was not changed.

## Verification

| Check | Result |
| --- | --- |
| `flutter analyze` | Passed: no issues found |
| `flutter test` | Passed: 11 tests, consisting of 7 parser tests and 4 widget tests |
| `flutter build apk --debug --no-pub` | Passed: Android debug APK built |
| Native end-to-end behavior | Not exercised: no connected Android device or configured emulator; iOS runtime unavailable on this Windows machine |
| Live social-provider compatibility | Not verified; fixture parser tests do not establish that current provider responses work |

The existing widget tests mock native method channels. Passing them does not verify background transfers, share-sheet handoff, session persistence, permissions, or export on a device.

## Fix before a wider beta

### 1. Complete the iPhone Instagram download flow, or label it unavailable

**Confirmed functional gap.** The Instagram branch of `save()` opens the website and returns. After navigation, the controller switches to `connected`, and the only enabled action becomes Disconnect Instagram. There is no authenticated media resolver or Instagram queueing step. Consequently, connecting Instagram does not save the shared post, and that Instagram branch does not even enqueue a pending fallback.

Evidence: [ShareViewController.swift:112](../ios/ShareExtension/ShareViewController.swift#L112), [ShareViewController.swift:256](../ios/ShareExtension/ShareViewController.swift#L256). The existing implementation plan also leaves resolver Task 2 unchecked. [README.md:40](../README.md#L40) currently promises that repeat shares resolve and queue media.

**Improve:** finish the existing authenticated resolver plan after its signed-iPhone feasibility checkpoint, including ordered carousel queueing and clear failures. Until then, remove the completed-feature claim and explicitly mark Instagram sharing experimental/unavailable.

**Acceptance:** an actual Reel, photo, and mixed carousel each appear in Downloads after sharing; a later share reuses the session; an expired session offers a useful recovery action.

### 2. Make Android sharing accept the social links supported by paste

**Confirmed functional gap.** Android `sharedVideo()` accepts only direct file URLs. Sharing an X, Pinterest, Instagram, or YouTube post produces the instruction to share a direct MP4/image link, while pasting supported post URLs into the main app takes a resolver path.

Evidence: [ShareActivity.kt:46](../android/app/src/main/kotlin/com/adesmith001/clipshare/ShareActivity.kt#L46), [main.dart:121](../lib/main.dart#L121).

**Improve:** accept supported social URLs and preserve them for the existing Flutter resolver. A pending-link handoff is sufficient for beta; a second native provider implementation is unnecessary. Clearly tell the user when opening ClipShare is required to continue.

**Acceptance:** share a supported post with ClipShare closed and already open; the link appears once and can be downloaded without copying it manually.

### 3. Prevent unmanageable pending entries

**Confirmed functional gap.** The iOS extension accepts general HTTP/HTTPS web URLs and saves non-direct, non-Instagram links as pending. The main screen only supplies a download action for recognized social URLs or direct images. An unsupported site, TikTok link, or HTTP URL can therefore become a permanent pending entry with no action. Repeated pending shares are also not deduplicated.

Evidence: [SharedLinks.swift:37](../ios/SharedLinks.swift#L37), [ShareViewController.swift:130](../ios/ShareExtension/ShareViewController.swift#L130), [main.dart:498](../lib/main.dart#L498).

**Improve:** validate supported links at intake; explain unsupported links before accepting them; normalize and deduplicate pending shares; give every stored entry an actionable state and a Remove option. Keep the platform support rules consistent.

**Acceptance:** unsupported links produce an immediate explanation; repeated shares do not accumulate dead rows; every existing pending row can be processed or removed.

### 4. Add deletion and storage management

**Missing essential control.** The UI offers export, cancel, and retry, but no delete/remove action for saved files, failures, or pending links. Files can accumulate through repeated beta use without an in-app cleanup path.

Evidence: [main.dart:470](../lib/main.dart#L470); the Android and iOS bridges expose no delete operation.

**Improve:** add Delete download and Remove entry, with confirmation or undo as appropriate. Delete the app's own media and metadata together, explain that exported Photos/Gallery copies remain, and show basic local storage usage. A full file manager is unnecessary.

**Acceptance:** removing a saved item frees its local storage, it stays removed after restart, and exported copies remain intact.

### 5. Isolate bad queue records and check interrupted transfers

**Confirmed persistence weakness:** iOS `entries()` throws if any one record cannot be decoded/read. The bridge then reports the entire library unavailable; new downloads also consult that same listing. One damaged record can therefore block otherwise healthy downloads.

Evidence: [SharedLinks.swift:108](../ios/SharedLinks.swift#L108), [AppDelegate.swift:25](../ios/Runner/AppDelegate.swift#L25), [BackgroundDownloads.swift:39](../ios/BackgroundDownloads.swift#L39).

**Improve:** isolate/quarantine an unreadable record, preserve access to healthy entries, and offer a recovery message. Separately, reconcile persisted downloading entries against actual native tasks on startup. Current iOS cancellation only recognizes tasks held in the current process's `appTasks` dictionary; whether interruption causes stale states needs device verification.

**Acceptance:** a malformed record does not hide healthy downloads; interrupted/relaunched transfers either continue, finish, or become explicitly retryable rather than remaining indefinitely downloading.

## Improve the beta experience

### 6. Show useful progress and error explanations

Provider resolution disables Add link without showing a resolving indicator. YouTube resolution alone can wait up to 25 seconds, plus an optional title request. Many distinct errors become “no supported image or video,” “couldn't reach the media provider,” or “couldn't complete that action.” The Instagram sign-in message says to try later even though the main-app resolver does not use the extension's session.

Evidence: [main.dart:151](../lib/main.dart#L151), [main.dart:223](../lib/main.dart#L223), [main.dart:625](../lib/main.dart#L625), [social_video.dart:199](../lib/social_video.dart#L199). Android collapses system download failures to `failed` without retaining the reason; iOS also persists only the terminal state.

**Improve:** display Resolving link, Queued, Downloading, and actionable failure states. Distinguish offline/timeout, authentication, unavailable media, and storage failures where the cause is known. Preserve sanitized native error details for diagnosis. Add Refresh/Try again to the unavailable-library state instead of requiring an app lifecycle change.

### 7. Give testers instructions and a feedback route

The empty state only says “No downloads yet.” There is no Help/About/feedback interface or visible build number.

Evidence: [main.dart:658](../lib/main.dart#L658).

**Improve:** add a short first-use explanation, a platform-specific supported-link list, the save-versus-export distinction, and a Report a problem action. Include app/build version, device/OS, provider, operation, and a sanitized error code in a copyable report. Keep full URLs, tokens, and session data out of automatic diagnostic reports. A small local report/export flow is enough for the first beta.

### 8. Expand release checks around native behavior

The only workflow builds/analyzes iOS; it does not run the Flutter test suite or build Android. It has no pull-request trigger, and automatic push builds are disabled for private repositories. The signed iOS path calls the export script without a test/analyze step. `RunnerTests.swift` is a placeholder. Android release configuration still uses debug signing.

Evidence: [.github/workflows/ios.yml:3](../.github/workflows/ios.yml#L3), [ios.yml:23](../.github/workflows/ios.yml#L23), [RunnerTests.swift](../ios/RunnerTests/RunnerTests.swift), [build.gradle.kts:32](../android/app/build.gradle.kts#L32), [export-development-ipa.sh:61](../ios/export-development-ipa.sh#L61).

**Improve:** gate candidate builds on analyze, existing tests, Android compilation, and iOS app/extension compilation. Use a stable release signing identity for distributed Android beta builds. Add focused coverage for pending-link intake, deduplication, retry, malformed persistence, and export denial/cancellation. Validate a signed upgrade preserves the library. Use a repeatable installation channel appropriate to the beta group; the current documented iPhone path is a registered-device development IPA.

### 9. Avoid repeatedly parsing the entire saved library

On Android, every `entries()` call revalidates each successful saved media file with image decoding or `MediaMetadataRetriever`. Flutter requests the list every two seconds while any download is active. This can make a growing library expensive to refresh even though the work runs on a background task queue.

Evidence: [AndroidDownloads.kt:129](../android/app/src/main/kotlin/com/adesmith001/clipshare/AndroidDownloads.kt#L129), [AndroidDownloads.kt:263](../android/app/src/main/kotlin/com/adesmith001/clipshare/AndroidDownloads.kt#L263), [main.dart:104](../lib/main.dart#L104).

**Improve:** validate when a transfer completes, retain that result, and recheck file existence or playback/export on demand. Check scrolling and transfer progress with a realistically populated library before deciding whether more optimization is needed.

### 10. Finish the small presentation details

The inspected Android launcher icon is the default Flutter logo. The iPhone Instagram view uses a fixed 380-point web view in a vertically centered stack; small screens, landscape, large text, and the login keyboard need visual checks.

Evidence: [ic_launcher.png](../android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png), [ShareViewController.swift:48](../ios/ShareExtension/ShareViewController.swift#L48), [ShareViewController.swift:152](../ios/ShareExtension/ShareViewController.swift#L152).

**Improve:** use a recognizable ClipShare icon and verify small-screen/large-text layouts, keyboard access, VoiceOver/TalkBack labels, and reachable share-sheet actions. Keep the existing palette and simple layout; a redesign is unnecessary before beta.

## Device checks for the beta candidate

| Scenario | Expected outcome |
| --- | --- |
| Direct MP4 with audio; JPEG, PNG, and WebP | Correct state, playback/preview, and availability after relaunch |
| Error-page or corrupt-media response | Failed with an explanation; never falsely Saved |
| Each advertised provider and supported post type | A real current link works through each advertised intake path |
| First Instagram login, later share, expired session | Media queues after success; authentication failure has a recovery route |
| Mixed carousel, duplicate share, partial failure | Original item ordering, no duplicate downloads, missing items retryable |
| Screen lock, backgrounding, connection loss, relaunch, force-close | A truthful terminal or continuing state with appropriate recovery |
| Cancel followed by retry | One replacement download and consistent state after relaunch |
| Photos permission denial; Files picker cancellation | Local media retained and still playable/exportable |
| Low storage; corrupted queue entry | Clear error and continued access to unaffected files |
| Signed build upgrade | Existing downloads remain accessible |
| Large library; small display; large text; screen reader | Responsive scrolling and usable controls |

Start with a small beta after the sharing gaps, pending-entry handling, deletion, and candidate-device checks are resolved. Search, folders, batch actions, quality selection, dark mode, and additional providers can follow tester evidence rather than delaying the first beta.
