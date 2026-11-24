# ClipShare

ClipShare is a personal downloader for media shared from social apps. Version `0.2.2+11` includes automatic platform folders, search, saved appearance and library settings, selection and batch actions, queue recovery, and beta diagnostics.

## Run the app

Install Flutter 3.50.0 and set up the Android SDK. Connect an Android device or start an emulator, then run these commands from the project root.

```sh
flutter pub get
flutter run
```

The app opens to Downloads. Paste a public Pinterest video Pin, a `pin.it` share link, an X video post, an Instagram Reel or video post, a YouTube video or Short, a public TikTok video or short share link, or a direct HTTPS MP4. ClipShare resolves Pinterest, X, Instagram, and YouTube posts on-device and chooses from the MP4 renditions each provider makes available. YouTube requires a stream with video and audio together. The palette uses deep plum (`#302435`), soft apricot (`#F5C5A5`), and warm ivory (`#FAF7F2`).

## Try Android sharing

Open a direct HTTPS link whose path ends in `.mp4` in a browser or messaging app. Share the link to **ClipShare** and tap **Download**. The confirmation closes and Android continues the transfer while you stay in the source app. Open ClipShare and tap **Play video** when the entry says **Saved**. Use a video with audio and verify that it still plays after relaunch.

For a failure check, share an MP4 URL that returns an error page. ClipShare should show **Download failed**. Sharing a supported social post adds one pending entry. Open ClipShare and use its download action to resolve the post. Unsupported links show an explanation instead of adding a pending entry.

## Manage downloads

Paste a supported URL into **Media link** and tap the **+** button beside it. The library shows thumbnails, post titles when available, and download status. Direct HTTPS JPEG and PNG links, Pinterest photo Pins, public Instagram photo posts and carousels, and photos and videos from public X posts use the same queue. Each available item in a multi-item post gets its own entry. Use **Photos** and **Videos** to filter the library. Tap a saved thumbnail to play the video or view the image. Use **Retry download** for failed or cancelled entries. Android can cancel active transfers. On iOS, Cancel appears for transfers started in the current ClipShare session. Transfers started in the Share Extension continue under iOS background scheduling.

Use **Save to Gallery** on Android 10 or later. On iOS, open the item's export menu and choose **Save to Photos** or **Save to Files**. ClipShare keeps its local copy if you dismiss the export picker or decline Photos access.

## Folders, search, and batch actions

Downloads are grouped into **Instagram**, **X**, **YouTube**, **TikTok**, **Pinterest**, and **Other** folders automatically, using the original post link. Folders appear as soon as a source has an entry, show saved/total counts, and include existing downloads. Tap a folder to open its media; use the back arrow to return to all downloads. The home screen shows only platform folders; media lists and selection controls appear when you open a folder or search. Manual folder creation and moving are no longer needed. Older folder metadata and local files are preserved for compatibility.

Tap the **search icon at the top right** to open search. Search matches titles, sources, and URL paths; URL tokens are excluded. Search combines with the current platform and Photos/Videos filter. Close search to clear its query. Tap **Select downloads**, or long-press an item, to select entries. **Select all visible** respects the current filters. Selected entries remain selected when filters change; check the selected count. Batch actions can delete, retry/download, cancel, or export eligible media. Deletion requires confirmation and keeps exported copies.

Open **Settings** from the top bar to choose **System**, **Light**, or **Dark** appearance, the default **All/Photos/Videos** filter, and **Newest first/Oldest first** ordering. Preferences are saved on the device and restored after relaunch. Settings also shows local media storage and links to help and diagnostics.

**Help and feedback** shows the version/build, local media storage, provider instructions, and a copyable diagnostic report. Reports exclude full URLs, media titles, folder names, passwords, and website sessions. Add reproduction steps and share the report manually with your beta organiser. Pull down to refresh the library.

## TikTok resolver

TikTok video downloads use [TikWM](https://www.tikwm.com/), a public third-party resolver. Only the public video link is sent, with tracking parameters removed; passwords, accounts, and website sessions are not sent. Long video URLs, `vm.tiktok.com`, `vt.tiktok.com`, and `/t/` shares are accepted. Signed MP4 URLs are checked against the TikTok/TikWM media hosts before queuing, and the native queues still validate downloaded files. TikTok photo slideshows, private/restricted/deleted posts and live streams are not supported. Service limits or provider changes can make a link temporarily unavailable; wait briefly and retry with a fresh link.

## Android release signing

Debug builds still work with `flutter run` and `flutter build apk --debug`. Distributed release builds require your own stable signing key. Copy `android/key.properties.example` to the ignored `android/key.properties` and fill in the existing keystore location, store password, alias, and key password. Paths are relative to `android/`, or can be absolute paths with forward slashes.

CI can supply `CLIPSHARE_STORE_FILE`, `CLIPSHARE_STORE_PASSWORD`, `CLIPSHARE_KEY_ALIAS`, and `CLIPSHARE_KEY_PASSWORD` instead. The keystore must exist. Missing release configuration fails with a clear error; release builds never fall back to the debug key. Keystores and local signing properties are ignored by Git.

```sh
flutter build apk --release
# Or, for an Android testing track:
flutter build appbundle --release
```

## Build and install on iPhone

The **Beta checks and iOS build** workflow analyzes/formats/tests Flutter, builds Android and native test sources, compiles Runner and its embedded Share Extension, and runs the native iOS regression suite in a simulator. Signed exports depend on those checks. Run the signed build from a private GitHub repository so the IPA and its embedded device profiles are available only to users with repository access.

1. Register the iPhone with your Apple development team. Enable `group.com.adesmith001.clipshare` on the explicit App IDs `com.adesmith001.clipshare` and `com.adesmith001.clipshare.ShareExtension`.
2. Create an Apple Development signing certificate and a development provisioning profile for each App ID. Include the iPhone and the App Group in both profiles.
3. Under **Settings → Secrets and variables → Actions** in the private repository, set the repository variable `APPLE_TEAM_ID`. Add the repository secrets `IOS_CERTIFICATE_BASE64`, `IOS_CERTIFICATE_PASSWORD`, `IOS_RUNNER_PROFILE_BASE64`, and `IOS_EXTENSION_PROFILE_BASE64`. Use base64 for the exported certificate with its private key (`.p12`) and the two `.mobileprovision` files.
4. In **Actions → Beta checks and iOS build → Run workflow**, turn on **Export a signed development IPA**. Download the `ClipShare-development-ipa` artifact and enable Developer Mode on the iPhone if prompted.
5. Try `xtool install <path-to-ipa>` from WSL with the iPhone paired over USB. If re-signing changes the App Group, use `ideviceinstaller install <path-to-ipa>` to install the CI-signed IPA directly.

To verify the handoff, open a page in Safari, share it to ClipShare, and tap **Add to ClipShare**. Safari should stay foregrounded. Open ClipShare and check that the link appears once as **Pending download**, then close and reopen the app to check that the entry persists.

For Instagram on iPhone, choose **ClipShare** from Instagram's share sheet. On the first use, sign in on Instagram's page shown inside the share sheet; ClipShare keeps the session in the extension's on-device WebKit store and does not collect your password. After that, sharing an Instagram Reel, photo, or carousel to ClipShare resolves and queues its supported media without opening the main app. If Instagram expires or challenges the session, sign in again in the share sheet. Use **Disconnect Instagram** there to clear the saved website session.

Other supported social posts shared to ClipShare appear as deduplicated pending entries. Open ClipShare and tap **Download media** on a pending post. Public TikTok video links are supported through TikWM; short share links are resolved when you open their TikTok folder and tap Download media. Pasting an Instagram link into the main app does not use the Share Extension's Instagram session.

To verify a download, open and share a direct HTTPS URL whose path ends in `.mp4`. Use a video you have permission to download and that has audio. Tap **Download** and stay in Safari until the transfer has had time to finish. Open ClipShare, check that the entry says **Saved**, and tap **Play video**. Verify that the video plays with audio and remains available after relaunch. An MP4 URL returning an error page should instead show **Download failed**.

## Beta verification

See [the beta testing checklist](docs/beta-testing.md) for device scenarios, installation/signing requirements, and native test commands. Automated parser and mocked-widget checks do not prove that a live provider or the signed share extension works on a device. In particular, Instagram embedded sign-in, session reuse, background transfers, and app upgrades need signed-iPhone verification before a wider beta.

```sh
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --debug --no-pub
```

## Store update 0.2.2 (11)

Store builds now accept the same supported social links as personal builds. `STORE_BETA=true` selects the existing store package/bundle IDs, App Group, display name, and signing keys; it must not restrict link resolution. Keep using it for upgrades to the existing store listings.

Build Android with `flutter build appbundle --release --dart-define=STORE_BETA=true`. The signed bundle is `build/app/outputs/bundle/release/app-release.aab`. The private iOS repository's **Store beta build** workflow produces the signed IPA for TestFlight. Existing installed version 0.2.1 (10) needs an app update to receive this fix.

Update the store description/release notes to mention supported social links. Version 0.2.2's privacy policy at `/privacy` discloses TikWM network requests and optional Instagram sign-in on iOS. Review the store Data safety/App Privacy answers against these practices when submitting the update.
