# Instagram Authenticated Share Downloads Implementation Plan

> **For agentic workers:** Implement inline, task by task, with a build and iPhone checkpoint between the authentication shell and the resolver.

**Goal:** Let a user sign in to Instagram once inside ClipShare's iOS Share Extension, then queue Reels, photos, and supported carousel slides from Instagram's share sheet without opening the main ClipShare app.

**Architecture:** The Share Extension owns a persistent `WKWebView` using `WKWebsiteDataStore.default()`. It loads Instagram pages so WebKit applies its own session cookies, detects login redirects, and reads embedded public media data from the loaded page. A native resolver queues each validated media URL through the existing App Group `BackgroundDownloads` flow; no raw cookies are copied to app storage, and no Instagram URL or credential is sent to a ClipShare backend.

**Tech Stack:** Swift 5, UIKit, WebKit, Foundation `URLSession`, existing App Group queue and background `URLSession` download delegate, GitHub Actions signed iOS build.

**Spec:** `docs/superpowers/specs/2026-11-16-instagram-authenticated-share-downloads-design.md`

## Global Constraints

- Instagram login is rendered by Instagram in a `WKWebView`; ClipShare must never collect or log the user's password.
- Keep Instagram website data in the Share Extension's persistent WebKit store; do not copy session cookies into files, shared defaults, Keychain, logs, or a remote service.
- Attach Instagram session data only through WebKit for Instagram page navigation; never send it to media CDN hosts.
- Keep using App Group `group.com.adesmith001.clipshare` and the existing native background download queue for downloaded media.
- A session challenge or expiry must retain the shared URL, let the user reauthenticate, then retry that URL once.
- If Instagram blocks authentication in the embedded WebKit view, stop and report the limitation instead of adding cookie extraction workarounds.
- Preserve existing Android, X, Pinterest, YouTube, and direct-media resolver paths.

---

### Task 1: Add persistent Instagram sign-in to the Share Extension

**Files:**
- Modify `ios/ShareExtension/ShareViewController.swift`
- Modify `pubspec.yaml`
- Modify `README.md`

**Interfaces:**
- The extension retains the shared Instagram URL while it displays Instagram's first-party sign-in page.
- `WKWebView` uses `WKWebsiteDataStore.default()` and is retained by the Share Extension view controller for the whole share-sheet session.
- After a sign-in navigation completes, the extension reloads the retained shared URL. This task only proves login and session reuse; social media resolution remains for Task 2.

- [x] Create a `WKWebView` with the default persistent website data store and add it to the extension view with Auto Layout.
- [x] Add a controller state for link checking, sign-in, retry, connected, and idle; keep Cancel and the shared URL visible in appropriate states.
- [x] Load the shared Instagram URL first. If WebKit navigates to an Instagram `/accounts/login` route, keep the current web view visible for the user to sign in on Instagram.
- [x] When the user finishes Instagram sign-in and leaves the login route, reload the retained shared URL in the same web view and display a connected/ready state.
- [x] Add a **Disconnect Instagram** action that deletes Instagram cookies and website data from the extension's default `WKWebsiteDataStore`.
- [x] Keep direct HTTPS media behavior unchanged and keep non-Instagram social links in the existing pending-link flow.
- [x] Increment the app version to `0.1.6+8` so the feasibility build installs as an update on the current iPhone build.
- [x] Update the iOS sharing instructions in `README.md` to describe first-time sign-in inside the share sheet.
- [ ] Commit and push this feasibility milestone, dispatch the signed iOS build, install it when the iPhone is available, and ask the user to sign in and share the same Instagram post again to verify the WebKit session persisted.

### Task 2: Resolve and queue Instagram media in the extension

**Files:**
- Create `ios/ShareExtension/InstagramResolver.swift`
- Modify `ios/ShareExtension/ShareViewController.swift`
- Modify `ios/Runner.xcodeproj/project.pbxproj`

**Interfaces:**
- `InstagramResolver.resolve(url:in:completion:)` loads the canonical post URL into the supplied `WKWebView` and returns `Result<InstagramResolvedPost, InstagramResolveError>`.
- `InstagramResolvedPost` contains `source: URL`, `title: String?`, and ordered `[InstagramResolvedItem]`.
- `InstagramResolvedItem` contains `url: URL`, zero-based `slot: Int`, and optional one-based `position: String?`.
- `InstagramResolveError` distinguishes `signInRequired`, `unavailable`, and `networkFailure` for extension messaging.

- [ ] Add `InstagramResolver.swift` to the Share Extension group and target's Compile Sources build phase.
- [ ] Extract the Instagram shortcode from `/p/`, `/reel/`, `/reels/`, `/tv/`, and `/share/p/` or `/share/reel/` links; canonicalize resolution to `https://www.instagram.com/p/<code>/`.
- [ ] Load the canonical post in the extension's authenticated `WKWebView`; detect `/accounts/login` navigation and return `signInRequired` without losing the original URL.
- [ ] After the post page finishes loading, use `evaluateJavaScript` to read only `application/json` script contents containing `xig_polaris_media`; parse JSON recursively and select the media object whose `code` matches the shared shortcode.
- [ ] Resolve a single video from the largest available direct `.mp4` in `video_versions`; resolve images from the largest supported `.jpg`, `.jpeg`, `.png`, or `.webp` image candidate; only accept Instagram CDN hosts.
- [ ] Resolve carousel slides in source order, preserving original `slot` and `position` even when unsupported slides are skipped.
- [ ] In `ShareViewController`, pass each result to `BackgroundDownloads.start(item.url, source: post.source, title: post.title, slot: item.slot, position: item.position)` and count queued, already-present, and unsupported items for the confirmation message.
- [ ] Close the extension after the supported items are queued. Keep it open with an actionable message if authentication is required, no supported media is available, or the provider is unavailable.
- [ ] Commit and push the resolver milestone, dispatch the signed iOS build, and install it on the iPhone for share-sheet verification.

### Task 3: Complete the share-sheet session flow and document behavior

**Files:**
- Modify `ios/ShareExtension/ShareViewController.swift`
- Modify `ios/ShareExtension/InstagramResolver.swift`
- Modify `README.md`

**Interfaces:**
- A successful connected share queues media directly and closes the extension; the main ClipShare app is not launched.
- Expired sessions offer Instagram sign-in in the same view and retry the retained URL once.
- Disconnect clears only Instagram website data associated with the Share Extension's default website store.

- [ ] Handle a login redirect that occurs after a previously working session by presenting the existing web view and retaining the same shared URL for one post-login retry.
- [ ] Handle Instagram's checkpoint, private/deleted post, rate-limit, zero-supported-media, duplicate-download, and partial-carousel outcomes with distinct user-facing status text.
- [ ] Ensure all authenticated page navigation stays on Instagram hosts and the downloaded media requests go only to validated CDN URLs without Instagram cookies.
- [ ] Confirm the extension's App Group and background download session setup are unchanged; no new profile entitlements are introduced for authentication storage.
- [ ] Document Instagram first sign-in, repeat-share behavior, reauthentication, and disconnect in the iPhone README instructions.
- [ ] Build the signed IPA through the private workflow and install it on the registered iPhone. Have the user verify one Reel, one photo, a mixed carousel, a subsequent share without sign-in, and the reauthentication state after disconnect.
- [ ] Commit and push the completed milestone after the signed build and iPhone handoff are verified.

## Plan self-review

- Spec coverage maps to Task 1 for sign-in and persistent WebKit session, Task 2 for authenticated media resolution and direct queueing, and Task 3 for expiry, disconnect, errors, and on-device verification.
- No cookie extraction or shared keychain transfer is present in the plan.
- The resolver result names and parameter types remain consistent between Tasks 2 and 3.
- Android and existing providers remain out of scope.
- The feasibility checkpoint precedes implementation of authenticated media parsing, so an Instagram embedded-login block stops further work before cookie handling is expanded.
