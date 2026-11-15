# Instagram Sign-In and Share-Sheet Downloads

**Status:** Approved for implementation  
**Date:** 2026-11-16

## Goal

Let a ClipShare user connect Instagram once, then save accessible Instagram Reels, single photos, and every supported item in a carousel directly from Instagram's iOS share sheet. The user should not have to switch to the ClipShare app for each post.

## Current behavior

ClipShare's iOS Share Extension accepts a URL and puts social links into the shared download queue as `pending`. The Flutter app resolves those links after the user opens ClipShare. The Dart Instagram resolver requests the post without an authenticated session. Instagram is currently redirecting anonymous requests to its sign-in page, so the resolver receives no media data.

## Chosen approach

Use Instagram's first-party website login in a `WKWebView` owned by ClipShare's Share Extension. The extension's persistent WebKit website data store retains the Instagram session on-device. ClipShare will not provide a password form or transmit session data to a ClipShare server.

The official Instagram API is not selected because it requires an Instagram or Facebook access token and is scoped to professional-account media use cases. It does not meet the requirement to save arbitrary public posts shared from Instagram.

## User flow

1. The user chooses **Share** in Instagram and selects ClipShare.
2. If ClipShare has no usable Instagram session, the extension presents Instagram's own sign-in page. The shared post URL remains in memory while sign-in completes.
3. After sign-in, ClipShare resolves the shared post, presents a concise result, and queues each supported media item through the existing App Group download queue.
4. On later shares, the extension reuses its on-device WebKit session, resolves the post, queues the downloads, and closes. The user can see completion and manage saved files the next time ClipShare is opened.
5. If Instagram expires or challenges the session, the extension asks the user to sign in again and retries the current shared post after successful sign-in.

The first sign-in and any later reauthentication occur in the share sheet. Normal shares do not require opening the ClipShare app.

## Components and data flow

- **`ShareViewController`** receives the shared URL, checks the extension's Instagram session, and coordinates sign-in, resolve, and queue states.
- **A native Instagram resolver in the Share Extension target** requests the shared post using the extension's session, parses the matching post data, and returns a caption/title plus ordered media URLs. It supports a single Reel/video, a single photo, and mixed or all-photo/all-video carousels. Unsupported or unavailable slide entries are skipped while preserving their original slide numbering.
- **`WKWebsiteDataStore`** owns the persistent Instagram website session. The extension loads Instagram post pages in its `WKWebView`, letting WebKit attach the session itself, then reads the rendered page's embedded media data. ClipShare does not extract, copy, or persist raw session cookies outside WebKit. Requests to Instagram's CDN use the media URL without forwarding Instagram authentication cookies.
- **Existing `SharedLinks` and `BackgroundDownloads`** persist queue entries and download media to the App Group container. The extension closes after all supported items have been queued; the existing Downloads screen displays progress and results.

The Flutter resolver remains responsible for Android and manual links added in the app. iOS shares use the native resolver so the authenticated WebKit session can be used within the extension process.

## Session and failure handling

- ClipShare never asks the user to enter an Instagram password into a ClipShare-owned form. The user interacts with Instagram's first-party sign-in page.
- The website session persists in the Share Extension's WebKit store. It is not copied into shared files or sent to a service. A **Disconnect Instagram** action in the extension removes Instagram cookies and website data from that store.
- Login challenges, account checkpoints, rate limits, private posts, deleted posts, and unavailable media produce a clear message and do not create false `Saved` entries.
- When an Instagram session is invalid, the extension offers reauthentication and retries the shared URL once sign-in completes. Session persistence is subject to Instagram's expiry and revocation rules; ClipShare cannot promise a sign-in will last indefinitely.
- Media downloads continue using the existing background download sessions and remain visible in ClipShare's shared Downloads library.

## Feasibility checkpoint

Before completing the resolver and download flow, build a minimal Share Extension sign-in screen and confirm on the user's iPhone that Instagram permits sign-in in the embedded WebKit view and that the extension can still read the persisted session on a later share invocation. If Instagram blocks embedded sign-in or the session cannot be reused by the extension, stop before adding cookie workarounds and return with the platform limitation and alternatives for a new decision.

## Acceptance criteria

- The ClipShare action remains available for Instagram links in the iOS share sheet.
- A first Instagram share can complete Instagram's own sign-in in the extension and resume the same shared post afterward.
- A later share reuses the session without prompting while Instagram considers it valid.
- A Reel/video, a single image, and each supported slide of a mixed carousel can be queued without switching to the main app.
- The extension never exposes the Instagram password to ClipShare code or a ClipShare server.
- Session expiry or blocked/unsupported posts report an actionable status; they are not marked saved.
- Existing X, Pinterest, YouTube, direct-media, and Android flows remain on their current resolver paths.

## Verification plan

Use signed iPhone builds and manual checks in Instagram's share sheet for first sign-in, a subsequent share, a Reel, a single image, a mixed carousel, and a session-expired or unavailable post. Inspect the shared Downloads library after opening ClipShare. Confirm the signed app and extension entitlements and that no Instagram cookie or password is written to logs or shared files.

## Source references

- [Apple `WKHTTPCookieStorage` and per-app/per-extension cookie stores](https://developer.apple.com/documentation/foundation/httpcookiestorage/)
- [Apple app extension data sharing](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionOverview.html)
- [Meta Instagram Media API access requirements](https://developers.facebook.com/docs/instagram-platform/reference/instagram-media/v21.0/)
