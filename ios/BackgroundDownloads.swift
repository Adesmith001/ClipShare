import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

final class BackgroundDownloads: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  static let sessionPrefix = "com.adesmith001.clipshare.share-download."
  static let appSessionPrefix = "com.adesmith001.clipshare.app-download."
  static var didChange: (() -> Void)?
  private static var appTasks: [String: URLSessionDownloadTask] = [:]
  private static var appDownloads: [String: BackgroundDownloads] = [:]
  private static var sessions: [String: URLSession] = [:]
  private static var verifying: Set<String> = []
  // Isolated queue fixtures can exercise persistence without starting OS transfers.
  static var testTaskStarter: ((URL) -> Void)?

  private let id: String
  private let identifier: String
  private var completion: (() -> Void)?
  private let verification = DispatchGroup()

  init(id: String, identifier: String, completion: (() -> Void)? = nil) {
    self.id = id
    self.identifier = identifier
    self.completion = completion
  }

  private func makeSession() -> URLSession {
    let configuration = URLSessionConfiguration.background(
      withIdentifier: identifier
    )
    configuration.sharedContainerIdentifier = SharedLinks.appGroup
    return URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
  }

  static func start(
    _ url: URL, inApp: Bool = false, source: URL? = nil, replacingID: String? = nil,
    title: String? = nil, slot: Int = 0, position: String? = nil, sourceAlias: URL? = nil,
    folder: String? = nil
  ) throws -> Bool {
    let isVideo = source == nil ? SharedLinks.isDirectVideo(url) : SharedLinks.isResolvedVideo(url)
    let imageExtension = SharedLinks.imageExtension(url)
    guard (isVideo || imageExtension != nil), slot >= 0 else { throw URLError(.unsupportedURL) }
    return try SharedLinks.withQueueLock {
      guard let original = SharedLinks.canonicalSource(source ?? url) else { throw URLError(.unsupportedURL) }
      let key = SharedLinks.downloadKey(original)
      let aliasKey = sourceAlias.flatMap(SharedLinks.canonicalSource).map(SharedLinks.downloadKey)
      let entries = try SharedLinks.entries()
      let previous = replacingID.flatMap { id in entries.first { $0.id == id } } ??
        (source == nil ? nil : entries.first {
          guard $0.state == .pending, let url = URL(string: $0.url) else { return false }
          let pendingKey = SharedLinks.downloadKey(url)
          return pendingKey == key || pendingKey == aliasKey
        })
      if replacingID != nil && previous == nil { return false }
      if let previous, !(previous.state == .failed || previous.state == .cancelled || (source != nil && previous.state == .pending)) { return false }
      if let duplicate = entries.first(where: { entry in
        guard entry.state == .downloading || entry.state == .saved,
              let existing = URL(string: entry.url)
        else { return false }
        return SharedLinks.downloadKey(existing) == key && (entry.slot ?? 0) == slot
      }) {
        var existing = duplicate
        if let aliasKey { existing.aliases = Array(Set((existing.aliases ?? []) + [aliasKey])) }
        if let previous, previous.state == .pending {
          existing.aliases = Array(Set((existing.aliases ?? []) + (previous.aliases ?? []) + [SharedLinks.downloadKey(URL(string: previous.url)!)]))
          try SharedLinks.save(existing)
          try SharedLinks.removeFiles(previous.id)
          return true
        }
        try SharedLinks.save(existing)
        return false
      }

      let fallbackFolder = entries.first(where: { URL(string: $0.url).map(SharedLinks.downloadKey) == key && !($0.folder ?? "").isEmpty })?.folder
      let chosenFolder = folder ?? previous.map { $0.folder ?? "" } ?? fallbackFolder ?? ""
      let folders = try SharedLinks.folders()
      guard chosenFolder.isEmpty || folders.contains(chosenFolder) else { throw URLError(.badURL) }

      var entry = try SharedLinks.enqueue(
        original, state: .downloading, imageExtension: imageExtension, title: title,
        slot: slot, position: position
      )
      let prefix = inApp ? appSessionPrefix : sessionPrefix
      entry.folder = chosenFolder
      entry.aliases = previous.map { ($0.aliases ?? []) + [SharedLinks.downloadKey(URL(string: $0.url)!)] } ??
        entries.first(where: { URL(string: $0.url).map(SharedLinks.downloadKey) == key })?.aliases
      if let aliasKey { entry.aliases = Array(Set((entry.aliases ?? []) + [aliasKey])) }
      entry.sessionIdentifier = prefix + entry.id
      try SharedLinks.save(entry)
      if let previous {
        do {
          try SharedLinks.removeFiles(previous.id)
        } catch {
          try? FileManager.default.removeItem(at: SharedLinks.file(entry.id, suffix: "json"))
          throw error
        }
      }
      if let testTaskStarter { testTaskStarter(url); return true }
      let download = BackgroundDownloads(id: entry.id, identifier: prefix + entry.id)
      let session = download.makeSession()
      var request = URLRequest(url: url)
      if SharedLinks.isTikTokLink(original) {
        request.setValue("https://www.tiktok.com/", forHTTPHeaderField: "Referer")
        request.setValue("ClipShare/0.2", forHTTPHeaderField: "User-Agent")
      }
      let task = session.downloadTask(with: request)
      appTasks[entry.id] = task
      appDownloads[download.identifier] = download
      sessions[download.identifier] = session
      task.resume()
      return true
    }
  }

  static func reconnect(identifier: String, completion: @escaping () -> Void) -> Bool {
    guard let prefix = [sessionPrefix, appSessionPrefix].first(where: { identifier.hasPrefix($0) })
    else { return false }
    let id = String(identifier.dropFirst(prefix.count))
    if let running = appDownloads[identifier] {
      running.completion = completion
      return true
    }
    let download = BackgroundDownloads(id: id, identifier: identifier, completion: completion)
    appDownloads[identifier] = download
    sessions[identifier] = download.makeSession()
    return true
  }

  static func canCancel(_ id: String) -> Bool {
    guard let task = appTasks[id] else { return false }
    return task.state == .running || task.state == .suspended
  }

  static func cancel(_ id: String) throws -> Bool {
    try SharedLinks.withQueueLock {
      var entry = try SharedLinks.entry(id)
      guard entry.state == .downloading else { return false }
      entry.state = .cancelled
      entry.progress = nil
      entry.error = nil
      try SharedLinks.save(entry)
      appTasks.removeValue(forKey: id)?.cancel()
      return true
    }
  }

  static func delete(_ id: String) throws -> Bool {
    try SharedLinks.withQueueLock {
      _ = try SharedLinks.entry(id)
      // Every callback takes the same lock and requires an existing downloading entry.
      appTasks.removeValue(forKey: id)?.cancel()
      try SharedLinks.removeFiles(id)
      return true
    }
  }

  static func reconcile(protectedDataAvailable: Bool = true, completion: @escaping (Bool) -> Void) {
    guard protectedDataAvailable else { completion(true); return }
    let entries: [SharedLinks.Entry]
    do {
      try SharedLinks.withQueueLock {
        for var entry in try SharedLinks.entries() where entry.state == .saved {
          if !FileManager.default.fileExists(atPath: try SharedLinks.file(entry.id, suffix: entry.imageExtension ?? "mp4").path) {
            entry.state = .failed
            entry.error = "file_missing"
            entry.sizeBytes = 0
            try SharedLinks.save(entry)
          }
        }
      }
      entries = try SharedLinks.entries().filter { $0.state == .downloading }
    }
    catch { completion(false); return }
    let group = DispatchGroup()
    for entry in entries {
      group.enter()
      let expectedIdentifiers = [appSessionPrefix + entry.id, sessionPrefix + entry.id]
      let identifiers = entry.sessionIdentifier.flatMap { expectedIdentifiers.contains($0) ? [$0] : nil } ?? expectedIdentifiers
      let checks = DispatchGroup()
      var active = false // All task callbacks below run on the main queue.
      for identifier in identifiers {
        checks.enter()
        let session: URLSession
        if let existing = sessions[identifier] { session = existing }
        else {
          let download = BackgroundDownloads(id: entry.id, identifier: identifier)
          appDownloads[identifier] = download
          session = download.makeSession()
          sessions[identifier] = session
        }
        session.getAllTasks { tasks in
          DispatchQueue.main.async {
            if let task = tasks.compactMap({ $0 as? URLSessionDownloadTask }).first(where: { $0.state == .running || $0.state == .suspended }) {
              if (try? SharedLinks.entry(entry.id).state) == .downloading {
                active = true
                Self.appTasks[entry.id] = task
                // A suspended task is still scheduled; reconnect it instead of failing it.
                if task.state == .suspended { task.resume() }
              } else { task.cancel() }
            }
            checks.leave()
          }
        }
      }
      checks.notify(queue: .main) {
        if !active && !verifying.contains(entry.id) {
          try? SharedLinks.withQueueLock {
            guard var current = try? SharedLinks.entry(entry.id), current.state == .downloading else { return }
            current.state = .failed
            current.error = "interrupted"
            current.progress = nil
            try SharedLinks.save(current)
          }
        }
        group.leave()
      }
    }
    group.notify(queue: .main) { didChange?(); completion(true) }
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
  ) {
    try? SharedLinks.withQueueLock {
      guard totalBytesExpectedToWrite > 0,
            var entry = try? SharedLinks.entry(id), entry.state == .downloading
      else { return }
      let progress = min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
      guard progress - (entry.progress ?? 0) >= 0.05 else { return }
      entry.progress = progress
      try? SharedLinks.save(entry)
    }
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL
  ) {
    guard let entry = try? SharedLinks.entry(id), entry.state == .downloading else { return }
    let staging: URL
    do {
      guard let response = downloadTask.response as? HTTPURLResponse,
            (200..<300).contains(response.statusCode),
            response.url?.scheme?.lowercased() == "https"
      else { throw URLError(.badServerResponse) }
      if let ext = entry.imageExtension {
        guard let type = UTType(filenameExtension: ext)?.identifier,
              let source = CGImageSourceCreateWithURL(location as CFURL, nil),
              CGImageSourceGetType(source).map({ $0 as String }) == type,
              CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 32,
              ] as CFDictionary) != nil
        else { throw URLError(.cannotDecodeContentData) }
        try saveMedia(location, suffix: ext)
        return
      }
      guard ["video/mp4", "application/mp4", "application/octet-stream"].contains(response.mimeType ?? "")
      else { throw URLError(.cannotDecodeContentData) }
      // URLSession removes its temporary file when this delegate method returns.
      staging = try SharedLinks.file(id, suffix: "staging.mp4")
      let staged = try SharedLinks.withQueueLock { () -> Bool in
        guard (try? SharedLinks.entry(id).state) == .downloading else { return false }
        try FileManager.default.moveItem(at: location, to: staging)
        return true
      }
      guard staged else { return }
    } catch {
      finish(.failed, error: Self.failureCode(error))
      return
    }

    Self.verifying.insert(id)
    verification.enter()
    Task { @MainActor in
      defer { Self.verifying.remove(id); verification.leave() }
      do {
        let asset = AVURLAsset(url: staging)
        let playable = try await asset.load(.isPlayable)
        let video = try await asset.loadTracks(withMediaType: .video)
        guard playable, !video.isEmpty else { throw URLError(.cannotDecodeContentData) }
        guard (try? SharedLinks.entry(id).state) == .downloading else {
          try? FileManager.default.removeItem(at: staging)
          return
        }
        try saveMedia(staging, suffix: "mp4")
      } catch {
        try? FileManager.default.removeItem(at: staging)
        finish(.failed, error: Self.failureCode(error))
      }
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    Self.appTasks.removeValue(forKey: id)
    if let error {
      finish(.failed, error: Self.failureCode(error))
    }
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    verification.notify(queue: .main) {
      Self.appDownloads.removeValue(forKey: self.identifier)
      Self.sessions.removeValue(forKey: self.identifier)
      session.finishTasksAndInvalidate()
      self.completion?()
      self.completion = nil
    }
  }

  private func saveMedia(_ location: URL, suffix: String) throws {
    try SharedLinks.withQueueLock {
      guard var entry = try? SharedLinks.entry(id), entry.state == .downloading else {
        try? FileManager.default.removeItem(at: location)
        return
      }
      let destination = try SharedLinks.file(id, suffix: suffix)
      try FileManager.default.moveItem(at: location, to: destination)
      entry.sizeBytes = Int64((try destination.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0)
      entry.state = .saved
      entry.progress = nil
      entry.error = nil
      try SharedLinks.save(entry)
      Self.didChange?()
    }
  }

  static func failureCode(_ error: Error) -> String {
    let error = error as NSError
    if error.domain == NSCocoaErrorDomain || error.domain == NSPOSIXErrorDomain { return "storage_unavailable" }
    if error.domain == NSURLErrorDomain {
      switch error.code {
      case NSURLErrorTimedOut: return "timeout"
      case NSURLErrorBadServerResponse: return "http_error"
      case NSURLErrorCannotDecodeContentData, NSURLErrorCannotParseResponse, NSURLErrorBadURL, NSURLErrorUnsupportedURL: return "invalid_media"
      case NSURLErrorCancelled: return "interrupted"
      case NSURLErrorCannotWriteToFile, NSURLErrorCannotCreateFile, NSURLErrorCannotMoveFile: return "storage_unavailable"
      default: return "network"
      }
    }
    return "invalid_media"
  }

  private func finish(_ state: SharedLinks.Entry.State, error: String? = nil) {
    do {
      try SharedLinks.withQueueLock {
        var entry = try SharedLinks.entry(id)
        guard entry.state == .downloading else { return }
        entry.state = state
        entry.progress = nil
        entry.error = error
        try SharedLinks.save(entry)
        Self.didChange?()
      }
    } catch {
      NSLog("ClipShare could not update a download: %@", error.localizedDescription)
    }
  }
}
