import Foundation
import XCTest
@testable import Runner

final class RunnerTests: XCTestCase {
  override func setUpWithError() throws {
    SharedLinks.testDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: SharedLinks.testDirectory!, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    BackgroundDownloads.testTaskStarter = nil
    if let directory = SharedLinks.testDirectory { try FileManager.default.removeItem(at: directory) }
    SharedLinks.testDirectory = nil
  }

  func testDistributionAppGroup() {
    #if STORE_BETA
    XCTAssertEqual(SharedLinks.appGroup, "group.com.adesmith001.clipshare.beta")
    #else
    XCTAssertEqual(SharedLinks.appGroup, "group.com.adesmith001.clipshare")
    #endif
  }

  func testAllDistributionVariantsAcceptSocialAndDirectMedia() throws {
    for text in [
      "https://x.com/person/status/123",
      "https://www.instagram.com/reel/test/",
      "https://pin.it/abc",
      "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
      "https://vm.tiktok.com/ZExample/",
      "https://example.com/own-video.mp4",
      "https://example.com/own-photo.jpg",
    ] {
      let url = URL(string: text)!
      XCTAssertNotNil(SharedLinks.canonicalSource(url), text)
      XCTAssertTrue(try SharedLinks.enqueuePending(url), text)
    }
    XCTAssertEqual(try SharedLinks.entries().count, 7)
  }

  func testTikTokShortSharesAndExtensionlessVideoDownloads() throws {
    let source = URL(string: "https://www.tiktok.com/@creator/video/6742501081818877190?tracking=first")!
    let alias = URL(string: "https://vm.tiktok.com/ZExample/")!
    let media = URL(string: "https://v16.tiktokcdn-us.com/video/clip/?signature=example")!
    XCTAssertEqual(SharedLinks.canonicalSource(source)?.absoluteString, "https://www.tiktok.com/@_/video/6742501081818877190")
    XCTAssertNotNil(SharedLinks.canonicalSource(alias))
    XCTAssertNotNil(SharedLinks.canonicalSource(URL(string: "https://www.tiktok.com/t/ZExample/")!))
    XCTAssertNil(SharedLinks.canonicalSource(URL(string: "https://www.tiktok.com/@creator/photo/123")!))
    XCTAssertNil(SharedLinks.canonicalSource(URL(string: "https://vm.tiktok.com.evil.test/ZExample/")!))
    XCTAssertTrue(SharedLinks.isResolvedVideo(media))
    XCTAssertFalse(SharedLinks.isResolvedVideo(URL(string: "https://v16.tiktokcdn-us.com.evil.test/video/clip/")!))
    XCTAssertTrue(try SharedLinks.enqueuePending(alias))
    let pending = try XCTUnwrap(SharedLinks.entries().first)
    BackgroundDownloads.testTaskStarter = { _ in }
    XCTAssertTrue(try BackgroundDownloads.start(media, inApp: true, source: source, replacingID: pending.id, sourceAlias: alias))
    XCTAssertEqual(try SharedLinks.entries().count, 1)
    XCTAssertFalse(try SharedLinks.enqueuePending(alias))
    XCTAssertFalse(try SharedLinks.enqueuePending(URL(string: "https://www.tiktok.com/@another/video/6742501081818877190")!))
  }

  func testPendingCanonicalDedupeAndUnsupportedIntake() throws {
    XCTAssertTrue(try SharedLinks.enqueuePending(URL(string: "https://twitter.com/person/status/123?s=20")!))
    XCTAssertFalse(try SharedLinks.enqueuePending(URL(string: "https://x.com/person/status/123")!))
    XCTAssertFalse(try SharedLinks.enqueuePending(URL(string: "https://x.com/i/web/status/123")!))
    XCTAssertFalse(try SharedLinks.enqueuePending(URL(string: "https://mobile.x.com/i/web/status/123")!))
    XCTAssertEqual(SharedLinks.canonicalSource(URL(string: "https://www.pinterest.com/pin/a-post--123/")!), URL(string: "https://www.pinterest.com/pin/123/"))
    XCTAssertEqual(try SharedLinks.entries().count, 1)
    XCTAssertThrowsError(try SharedLinks.enqueuePending(URL(string: "https://example.com/article")!))
    XCTAssertNil(SharedLinks.canonicalSource(URL(string: "https://instagram.com.evil.test/p/abc/")!))
    XCTAssertNotNil(SharedLinks.canonicalSource(URL(string: "https://www.youtube.com/shorts/abcdefghijk")!))
  }

  func testCorruptRecordDoesNotHideLegacyOrHealthyEntry() throws {
    let entry = try SharedLinks.enqueue(URL(string: "https://example.com/video.mp4")!)
    try Data("{bad json".utf8).write(to: SharedLinks.testDirectory!.appendingPathComponent("broken.json"))
    let legacyID = "00000000000000000001-00000000-0000-0000-0000-000000000001"
    try "https://unsupported.example/post".write(to: SharedLinks.file(legacyID, suffix: "url"), atomically: true, encoding: .utf8)
    XCTAssertEqual(try SharedLinks.entries().count, 2)
    XCTAssertEqual(try SharedLinks.recoveredEntries(), 1)
    XCTAssertEqual(try SharedLinks.entries().count, 2)
    XCTAssertEqual(try SharedLinks.recoveredEntries(), 1)
    XCTAssertEqual(try SharedLinks.entry(entry.id).channelValue["folder"] as? String, "")
    XCTAssertTrue(try SharedLinks.createFolder("Legacy"))
    XCTAssertTrue(try SharedLinks.move([legacyID], folder: "Legacy"))
    XCTAssertEqual(try SharedLinks.entries().count, 2)
    XCTAssertEqual(try SharedLinks.entry(legacyID).folder, "Legacy")
    XCTAssertTrue(try BackgroundDownloads.delete(legacyID))
    XCTAssertEqual(try SharedLinks.entries().count, 1)
  }

  func testFolderValidationMovePrevalidationAndUnfiling() throws {
    XCTAssertTrue(try SharedLinks.createFolder("  Trips  "))
    XCTAssertFalse(try SharedLinks.createFolder("trips"))
    XCTAssertFalse(try SharedLinks.createFolder("Unfiled"))
    XCTAssertFalse(try SharedLinks.createFolder(String(repeating: "x", count: 61)))
    let entry = try SharedLinks.enqueue(URL(string: "https://example.com/photo.jpg")!, state: .saved, imageExtension: "jpg")
    try Data([1, 2, 3]).write(to: SharedLinks.file(entry.id, suffix: "jpg"))
    XCTAssertThrowsError(try SharedLinks.move([entry.id, "bad-id"], folder: "Trips"))
    XCTAssertNil(try SharedLinks.entry(entry.id).folder)
    XCTAssertTrue(try SharedLinks.move([entry.id], folder: "Trips"))
    XCTAssertTrue(try SharedLinks.renameFolder("Trips", to: "Favorites"))
    XCTAssertEqual(try SharedLinks.entry(entry.id).folder, "Favorites")
    try Data("broken".utf8).write(to: SharedLinks.testDirectory!.appendingPathComponent(".folders.json"))
    XCTAssertEqual(try SharedLinks.folders(), ["Favorites"])
    XCTAssertTrue(try SharedLinks.renameFolder("Favorites", to: nil))
    XCTAssertEqual(try SharedLinks.entry(entry.id).folder, "")
    XCTAssertTrue(FileManager.default.fileExists(atPath: try SharedLinks.file(entry.id, suffix: "jpg").path))
    XCTAssertTrue(try BackgroundDownloads.delete(entry.id))
    XCTAssertFalse(FileManager.default.fileExists(atPath: try SharedLinks.file(entry.id, suffix: "jpg").path))
  }

  func testPendingAliasIsConsumedWhenResolvedMediaAlreadyExists() throws {
    let source = URL(string: "https://www.pinterest.com/pin/123/")!
    let pending = try SharedLinks.enqueue(URL(string: "https://pin.it/alias")!)
    let saved = try SharedLinks.enqueue(source, state: .saved, imageExtension: "jpg", slot: 0)
    XCTAssertTrue(try BackgroundDownloads.start(URL(string: "https://cdn.example.com/photo.jpg")!, inApp: true, source: source, replacingID: pending.id))
    XCTAssertEqual(try SharedLinks.entries().map(\.id), [saved.id])
    XCTAssertFalse(try SharedLinks.enqueuePending(URL(string: "https://pin.it/alias")!))
    let nextPending = try SharedLinks.enqueue(source)
    XCTAssertTrue(try BackgroundDownloads.start(URL(string: "https://cdn.example.com/photo.jpg")!, inApp: true, source: source))
    XCTAssertThrowsError(try SharedLinks.entry(nextPending.id))
    let alias = URL(string: "https://pin.it/secondAlias")!
    let aliasPending = try SharedLinks.enqueue(alias)
    XCTAssertTrue(try BackgroundDownloads.start(URL(string: "https://cdn.example.com/photo.jpg")!, inApp: true, source: source, sourceAlias: alias))
    XCTAssertThrowsError(try SharedLinks.entry(aliasPending.id))
    XCTAssertFalse(try SharedLinks.enqueuePending(alias))
  }

  func testRequestedShortcodeAndCarouselSlots() throws {
    let json = #"{"data":{"xig_polaris_media":{"shortcode":"wanted","edge_media_to_caption":{"edges":[{"node":{"text":"A caption"}}]},"edge_sidecar_to_children":{"edges":[{"node":{"is_video":true,"video_url":"https://s.cdninstagram.com/first.mp4?token=secret"}},{"node":{"display_url":"https://evil.test/not-allowed.jpg"}},{"node":{"display_url":"https://s.fbcdn.net/last.jpg"}}]}}},"related":{"shortcode":"other","video_url":"https://s.cdninstagram.com/unrelated.mp4"}}"#
    let post = try XCTUnwrap(InstagramResolver.parse(["broken", json], shortcode: "wanted"))
    XCTAssertEqual(post.title, "A caption")
    XCTAssertEqual(post.total, 3)
    XCTAssertEqual(post.media.map(\.slot), [0, 2])
    XCTAssertEqual(post.media.last?.position, "3/3")
    XCTAssertNil(InstagramResolver.parse([json], shortcode: "missing"))
  }

  func testSignedInVersionsPreferVideoAndLargestSupportedImage() throws {
    let json = #"{"items":[{"code":"wanted","caption":{"text":"Signed in"},"carousel_media":[{"media_type":2,"video_versions":[{"url":"http://s.fbcdn.net/insecure.mp4","width":2000,"height":2000},{"url":"https://s.fbcdn.net/movie.mp4","width":1000,"height":1000}],"image_versions2":{"candidates":[{"url":"https://s.fbcdn.net/poster.jpg"}]}},{"media_type":1,"image_versions2":{"candidates":[{"url":"https://s.cdninstagram.com/small.jpg","width":100,"height":100},{"url":"https://s.cdninstagram.com/large.webp","width":1000,"height":1000}]}}]}]}"#
    let post = try XCTUnwrap(InstagramResolver.parse([json], shortcode: "wanted"))
    XCTAssertEqual(post.media.map { $0.url.lastPathComponent }, ["movie.mp4", "large.webp"])
    XCTAssertEqual(post.media.map(\.slot), [0, 1])
  }

  func testSafeDownloadFailureCodes() {
    XCTAssertEqual(BackgroundDownloads.failureCode(URLError(.timedOut)), "timeout")
    XCTAssertEqual(BackgroundDownloads.failureCode(URLError(.notConnectedToInternet)), "network")
    XCTAssertEqual(BackgroundDownloads.failureCode(URLError(.badServerResponse)), "http_error")
    XCTAssertEqual(BackgroundDownloads.failureCode(URLError(.cannotDecodeContentData)), "invalid_media")
    XCTAssertEqual(BackgroundDownloads.failureCode(CocoaError(.fileWriteOutOfSpace)), "storage_unavailable")
  }

  func testReconcileMakesMissingSavedFileRetryable() throws {
    var entry = try SharedLinks.enqueue(URL(string: "https://example.com/lost.mp4")!, state: .saved)
    entry.folder = "Trips"
    try SharedLinks.save(entry)
    BackgroundDownloads.reconcile(protectedDataAvailable: false) { XCTAssertTrue($0) }
    XCTAssertEqual(try SharedLinks.entry(entry.id).state, .saved)
    let reconciled = expectation(description: "reconciled")
    BackgroundDownloads.reconcile { success in
      XCTAssertTrue(success)
      reconciled.fulfill()
    }
    wait(for: [reconciled], timeout: 5)
    let recovered = try SharedLinks.entry(entry.id)
    XCTAssertEqual(recovered.state, .failed)
    XCTAssertEqual(recovered.error, "file_missing")
    XCTAssertEqual(recovered.folder, "Trips")
    XCTAssertEqual(recovered.channelValue["canRetry"] as? Bool, true)
  }

  func testLateCallbacksDoNotResurrectDeletedOrCancelledEntries() throws {
    let url = URL(string: "https://example.com/video.mp4")!
    let task = URLSession.shared.downloadTask(with: url) // Never resumed; no network or App Group session.
    defer { task.cancel() }
    let entry = try SharedLinks.enqueue(url, state: .downloading)
    let delegate = BackgroundDownloads(id: entry.id, identifier: "test")
    XCTAssertTrue(try BackgroundDownloads.cancel(entry.id))
    delegate.urlSession(.shared, task: task, didCompleteWithError: URLError(.cancelled))
    XCTAssertEqual(try SharedLinks.entry(entry.id).state, .cancelled)
    XCTAssertTrue(try BackgroundDownloads.delete(entry.id))
    delegate.urlSession(.shared, downloadTask: task, didWriteData: 50, totalBytesWritten: 50, totalBytesExpectedToWrite: 100)
    delegate.urlSession(.shared, task: task, didCompleteWithError: URLError(.timedOut))
    let temporary = SharedLinks.testDirectory!.appendingPathComponent("callback.tmp")
    try Data([1]).write(to: temporary)
    delegate.urlSession(.shared, downloadTask: task, didFinishDownloadingTo: temporary)
    XCTAssertTrue(try SharedLinks.entries().isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: try SharedLinks.file(entry.id, suffix: "mp4").path))
  }

  func testCarouselResolutionFolderIsCapturedAndDoesNotMoveDuplicates() throws {
    BackgroundDownloads.testTaskStarter = { _ in }
    XCTAssertTrue(try SharedLinks.createFolder("Trips"))
    XCTAssertTrue(try SharedLinks.createFolder("Favorites"))
    let media = URL(string: "https://cdn.example.com/photo.jpg")!
    for chosenFolder in ["", "Favorites"] {
      let source = URL(string: "https://www.instagram.com/p/test\(chosenFolder.isEmpty ? "Unfiled" : "Favorites")/")!
      var old = try SharedLinks.enqueue(source, state: .saved, imageExtension: "jpg", slot: 0)
      old.folder = "Trips"
      try SharedLinks.save(old)
      var pending = try SharedLinks.enqueue(source)
      pending.folder = chosenFolder
      try SharedLinks.save(pending)
      XCTAssertTrue(try BackgroundDownloads.start(media, source: source, slot: 0, folder: chosenFolder))
      XCTAssertThrowsError(try SharedLinks.entry(pending.id))
      XCTAssertEqual(try SharedLinks.entry(old.id).folder, "Trips")
      XCTAssertTrue(try BackgroundDownloads.start(media, source: source, slot: 1, folder: chosenFolder))
      let added = try XCTUnwrap(SharedLinks.entries().first { $0.url == source.absoluteString && $0.slot == 1 })
      XCTAssertEqual(added.folder, chosenFolder)
      XCTAssertEqual(try SharedLinks.entry(old.id).folder, "Trips")
      var retry = try SharedLinks.enqueue(source, state: .failed, imageExtension: "jpg", slot: 3)
      retry.folder = "Trips"
      try SharedLinks.save(retry)
      XCTAssertTrue(try BackgroundDownloads.start(media, source: source, replacingID: retry.id, slot: 3, folder: chosenFolder))
      let retried = try XCTUnwrap(SharedLinks.entries().first { $0.url == source.absoluteString && $0.slot == 3 })
      XCTAssertEqual(retried.folder, chosenFolder)
      XCTAssertThrowsError(try SharedLinks.entry(retry.id))
      let count = try SharedLinks.entries().count
      XCTAssertThrowsError(try BackgroundDownloads.start(media, source: source, slot: 2, folder: "Unknown"))
      XCTAssertEqual(try SharedLinks.entries().count, count)
    }
  }
}
