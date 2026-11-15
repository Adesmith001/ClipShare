# ClipShare

ClipShare is a personal downloader for media shared from social apps.

## Run the app

Install Flutter 3.50.0 and set up the Android SDK. Connect an Android device or start an emulator, then run these commands from the project root.

```sh
flutter pub get
flutter run
```

The app opens to Downloads. Paste a public Pinterest video Pin, a `pin.it` share link, an X video post, or a direct HTTPS MP4 to start a download. ClipShare resolves public posts on-device and selects the highest-resolution Pinterest MP4 or the highest-bitrate MP4 for the first video in an X post. The palette uses deep plum (`#302435`), soft apricot (`#F5C5A5`), and warm ivory (`#FAF7F2`).

## Try Android sharing

Open a direct HTTPS link whose path ends in `.mp4` in a browser or messaging app. Share the link to **ClipShare** and tap **Download**. The confirmation closes and Android continues the transfer while you stay in the source app. Open ClipShare and tap **Play video** when the entry says **Saved**. Use a video with audio and verify that it still plays after relaunch.

For a failure check, share an MP4 URL that returns an error page. ClipShare should show **Download failed**. Sharing a post page shows the prompt to use a direct MP4 link.

## Manage downloads

Paste a supported video URL into **Video link** and tap **Add link**. An active or saved download for the same URL stays in the queue once. ClipShare shows percentages when the transfer reports a total size. Use **Retry download** for failed or cancelled entries. Android can cancel active transfers. On iOS, Cancel appears for transfers started in the current ClipShare session. Transfers started in the Share Extension continue under iOS background scheduling.

Use **Save to Gallery** on Android 10 or later. On iOS, open **Export video** and choose **Save to Photos** or **Save to Files**. ClipShare keeps its local copy if you dismiss the export picker or decline Photos access.

## Build and install on iPhone

The **iOS build** workflow compiles Runner and checks that the Share Extension is embedded. Run the signed build from a private GitHub repository so the IPA and its embedded device profiles are available only to users with repository access.

1. Register the iPhone with your Apple development team. Enable `group.com.adesmith001.clipshare` on the explicit App IDs `com.adesmith001.clipshare` and `com.adesmith001.clipshare.ShareExtension`.
2. Create an Apple Development signing certificate and a development provisioning profile for each App ID. Include the iPhone and the App Group in both profiles.
3. Under **Settings → Secrets and variables → Actions** in the private repository, set the repository variable `APPLE_TEAM_ID`. Add the repository secrets `IOS_CERTIFICATE_BASE64`, `IOS_CERTIFICATE_PASSWORD`, `IOS_RUNNER_PROFILE_BASE64`, and `IOS_EXTENSION_PROFILE_BASE64`. Use base64 for the exported certificate with its private key (`.p12`) and the two `.mobileprovision` files.
4. In **Actions → iOS build → Run workflow**, turn on **Export a signed development IPA**. Download the `ClipShare-development-ipa` artifact and enable Developer Mode on the iPhone if prompted.
5. Try `xtool install <path-to-ipa>` from WSL with the iPhone paired over USB. If re-signing changes the App Group, use `ideviceinstaller install <path-to-ipa>` to install the CI-signed IPA directly.

To verify the handoff, open a page in Safari, share it to ClipShare, and tap **Add to ClipShare**. Safari should stay foregrounded. Open ClipShare and check that the link appears once as **Pending download**, then close and reopen the app to check that the entry persists.

For a Pinterest video Pin or an X video post, share it to ClipShare the same way, then tap **Download video** on its pending entry in ClipShare. Instagram, TikTok, and YouTube post links still need provider support.

To verify a download, open and share a direct HTTPS URL whose path ends in `.mp4`. Use a video you have permission to download and that has audio. Tap **Download** and stay in Safari until the transfer has had time to finish. Open ClipShare, check that the entry says **Saved**, and tap **Play video**. Verify that the video plays with audio and remains available after relaunch. An MP4 URL returning an error page should instead show **Download failed**.

## Milestones

1. Initialize the Flutter app for iOS and Android.
2. Build a signed iPhone IPA on macOS CI and verify the native Share Extension and App Group on-device.
3. Prove a direct iOS download, then add Android sharing and downloads.
4. Add paste, queue controls, recovery, and media export.
5. Verify Pinterest, X, Instagram, and TikTok individually before packaging the personal builds.

Commit and push each verified milestone to GitHub.
