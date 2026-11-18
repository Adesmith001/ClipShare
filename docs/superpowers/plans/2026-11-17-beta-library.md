# Beta Library Implementation Plan

> Use subagent-driven-development for isolated native tasks and independent review; root integrates the Flutter UI. No automatic commits, pushes, or deployment.

Goal: implement beta review fixes plus folders, search, and batch actions.
Architecture: native queues retain persistence/download ownership, Flutter composes filtering and serial batch actions over the shared method-channel contract.
Tech: Flutter/Dart, Kotlin DownloadManager/SharedPreferences, Swift WebKit/URLSession, existing dependencies.
Spec: docs/superpowers/specs/2026-11-17-beta-library-design.md

## Constraints
Keep existing data readable; native schema fields optional/defaulted. No cookie extraction. Delete only app-owned content. No full URL in copied diagnostics. No new package required. No invented signing credentials. Flat local folders, serial batch operations.

## Tasks
- [x] Android queue/share/native contract and release config. Owned files android/**. Verify pending sharing, deletion, folder persistence/retry inheritance, cached validation, safe errors/info; compile with Flutter Android build.
- [x] Flutter library UI and tests. Owned files lib/**, test/**. Write failing widget tests first for title search, folder filtering/moving, selection, confirmed deletion. Implement folder CRUD dialogs, shared search/filter model, snapshot batch eligibility/results, resolving/error/refresh, Help/About/report. Existing test expectations remain supported.
- [x] iOS queue recovery/native contract/Instagram resolver. Owned files ios/**. Isolate corrupt entries, supported intake/dedupe, remove media safely, folder persistence, sanitized errors/info; background reconcile and cancellation. Native authenticated parser returns source/title/ordered items, uses WebKit scripts and CDN allowlist, queues once. Add native parser tests/CI test mechanism where possible; mark device validation pending.
- [x] Build/distribution and branding. Owned .github/**, docs/**, README.md, pubspec.yaml and launcher assets after native task ownership releases. Configure gates and release key requirements. Provide beta install/device checklist. Increment version/build.
- [x] Independent spec review then code-quality review, fix findings, run analyze/full tests/Android build, inspect rendered widget layouts; verify git diff and report remaining external checks.

## Test commands
C:/Users/USER/develop/flutter/bin/flutter.bat test --no-pub
C:/Users/USER/develop/flutter/bin/flutter.bat analyze --no-pub
C:/Users/USER/develop/flutter/bin/flutter.bat build apk --debug --no-pub

## Next action
Implementation and local verification complete. Follow docs/beta-testing.md for owner-supplied signing, macOS CI and device validation before wider beta.
