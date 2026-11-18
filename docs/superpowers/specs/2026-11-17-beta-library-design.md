# ClipShare beta library design

Date: 2026-11-17. Implements the beta review and the user's requested folders, search, and batch actions.

## Behavior
- Preserve the plum/apricot/ivory Downloads design; add a search field, folder filter, and selection toolbar with responsive wrapping.
- Folders are flat, local named collections, one folder per entry. All downloads and Unfiled are built-in views. Support create, rename, remove folder (unfiles entries, never deletes media), move entries. Names trim whitespace, 1-60 characters, unique ignoring case.
- Search is case-insensitive over title, source label/host, and URL path; it combines with media and folder filters. Query strings/tokens are not shown in diagnostics.
- Select individual items, select visible items, clear selection. Batch actions operate on a snapshot of selected entries, serially, report success/failure/skipped totals, disable repeat submission, refresh once. Actions: move, delete, retry/start pending, cancel active, save saved media to Photos/Gallery. Export uses existing native actions; no automatic external messages.
- Every entry can be removed; saved-media deletion asks confirmation and removes app-local media/metadata only. Exported copies remain. Folder deletion confirms and unfiles content.
- Show resolving state and actionable errors. Refresh unavailable library. Empty state explains share/paste and help explains supported providers, pending handoff, local copies, permissions, Instagram session, folders and beta diagnostics.
- Help/About shows app version/build/OS/local media bytes and offers copyable sanitized report (no URLs, titles, credentials, cookie data).
- Complete iOS Instagram authenticated parsing in WebKit and queue all supported slides using existing background downloads, without extracting cookies. Native runtime validation remains required on a signed iPhone.
- Android sharing accepts supported social URLs as deduplicated pending records; direct media still downloads without opening main app. Main app resolves pending links.
- Intake rejects unsupported links. iOS corrupted queue records are quarantined individually and healthy files stay visible. Reconcile background task state on launch; persist actionable failure codes.
- Android media validation is cached after completion and file existence is rechecked cheaply. Retain active transfer progress and safe failure reason.
- CI analyzes/tests/builds both platforms, includes PR/private pushes, verifies extension. Release Android requires configured release keystore rather than debug fallback. No credentials are invented. Replace default launcher assets with a simple ClipShare mark.

## Native channel contract (clipshare/shared_links)
Existing list/add/addResolved/play/thumbnail/preview/retry/cancel/export/saveToPhotos/exportToFiles stay compatible.
- list: List<Map>; optional fields folder:String (default empty), sizeBytes:int, error:String (safe code).
- folders: List<String> of user folders.
- createFolder(name:String), deleteFolder(name:String), renameFolder({from:String,to:String}): bool.
- move({ids:List<String>,folder:String}): bool. Empty folder means Unfiled. Validate all targets before mutation.
- delete(id:String): bool. Cancels if needed and removes local files/metadata, never external Gallery/Photos copies.
- info: {version:String,build:String,os:String,storageBytes:int,recoveredEntries:int}.
- reconcile: bool (safe to invoke on initial load); iOS checks OS download tasks before marking orphan records retryable.
- Retry/replacement retains folder. Pending records include stable IDs accepted by the existing String bridge. Folder names persist natively (no new Flutter dependency).

## Verification
Meaningful red/green widget tests for search, folder filtering/move, selection eligibility, delete confirmation, resolving/error and help. Parser tests for supported intake/Instagram shapes. Android build and tests; iOS CI checks compile on macOS. Document runtime tests not performed on this Windows host instead of claiming device success.
- Added optional addResolved.sharedSource (original resolver input URL). Native source remains canonical; original is retained as alias to reconcile pending raw/shortlinks and dedupe subsequent shares.

## Resolution folder clarification
- addResolved also accepts optional folder:String. Flutter snapshots a pending/retry entry's chosen folder once per resolve and sends it for every slide; an empty string explicitly means Unfiled. Equivalent source URLs use provider identity to find pending metadata. This prevents older saved slides in other folders from changing where newly resolved slides go.
- Already-saved or downloading duplicate entries retain their existing folders when re-shared; deduplication never silently moves existing content. New/replacement slides inherit the requested pending/retry folder. Use Move to folder to relocate existing content explicitly.
