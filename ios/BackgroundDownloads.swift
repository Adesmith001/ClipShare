import AVFoundation
import Foundation

final class BackgroundDownloads: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  static let sessionPrefix = "com.adesmith001.clipshare.share-download."
  static let appSessionPrefix = "com.adesmith001.clipshare.app-download."
  static var didChange: (() -> Void)?
  private static var appTasks: [String: URLSessionDownloadTask] = [:]
  private static var appDownloads: [String: BackgroundDownloads] = [:]

  private let id: String
  private let identifier: String
  private var completion: (() -> Void)?
  private let verification = DispatchGroup()

  private init(id: String, identifier: String, completion: (() -> Void)? = nil) {
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

  static func start(_ url: URL, inApp: Bool = false, retryID: String? = nil) throws -> Bool {
    guard SharedLinks.isDirectVideo(url) else { throw URLError(.unsupportedURL) }
    return try SharedLinks.withQueueLock {
      let key = SharedLinks.downloadKey(url)
      let entries = try SharedLinks.entries()
      if entries.contains(where: { entry in
        guard entry.state == .downloading || entry.state == .saved,
              let existing = URL(string: entry.url)
        else { return false }
        return SharedLinks.downloadKey(existing) == key
      }) { return false }

      if let retryID {
        let previous = try SharedLinks.entry(retryID)
        guard previous.state == .failed || previous.state == .cancelled else { return false }
      }

      let entry = try SharedLinks.enqueue(url, state: .downloading)
      if let retryID {
        do {
          try FileManager.default.removeItem(at: SharedLinks.file(retryID, suffix: "json"))
        } catch {
          try? FileManager.default.removeItem(at: SharedLinks.file(entry.id, suffix: "json"))
          throw error
        }
      }
      let prefix = inApp ? appSessionPrefix : sessionPrefix
      let download = BackgroundDownloads(id: entry.id, identifier: prefix + entry.id)
      let session = download.makeSession()
      let task = session.downloadTask(with: url)
      if inApp {
        appTasks[entry.id] = task
        appDownloads[entry.id] = download
      }
      task.resume()
      return true
    }
  }

  static func reconnect(identifier: String, completion: @escaping () -> Void) -> Bool {
    guard let prefix = [sessionPrefix, appSessionPrefix].first(where: { identifier.hasPrefix($0) })
    else { return false }
    let id = String(identifier.dropFirst(prefix.count))
    if let running = appDownloads[id] {
      running.completion = completion
      return true
    }
    _ = BackgroundDownloads(id: id, identifier: identifier, completion: completion).makeSession()
    return true
  }

  static func canCancel(_ id: String) -> Bool {
    appTasks[id]?.state == .running
  }

  static func cancel(_ id: String) throws -> Bool {
    guard let task = appTasks[id], task.state == .running else { return false }
    var entry = try SharedLinks.entry(id)
    guard entry.state == .downloading else { return false }
    entry.state = .cancelled
    entry.progress = nil
    try SharedLinks.save(entry)
    appTasks.removeValue(forKey: id)
    task.cancel()
    return true
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
  ) {
    guard totalBytesExpectedToWrite > 0,
          var entry = try? SharedLinks.entry(id), entry.state == .downloading
    else { return }
    let progress = min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    guard progress - (entry.progress ?? 0) >= 0.05 else { return }
    entry.progress = progress
    try? SharedLinks.save(entry)
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL
  ) {
    guard (try? SharedLinks.entry(id).state) == .downloading else { return }
    let staging: URL
    do {
      guard let response = downloadTask.response as? HTTPURLResponse,
            (200..<300).contains(response.statusCode),
            response.url?.scheme?.lowercased() == "https",
            ["video/mp4", "application/mp4", "application/octet-stream"].contains(response.mimeType ?? "")
      else { throw URLError(.badServerResponse) }
      // URLSession removes its temporary file when this delegate method returns.
      staging = try SharedLinks.file(id, suffix: "staging.mp4")
      try FileManager.default.moveItem(at: location, to: staging)
    } catch {
      finish(.failed)
      return
    }

    verification.enter()
    Task { @MainActor in
      defer { verification.leave() }
      do {
        let asset = AVURLAsset(url: staging)
        let playable = try await asset.load(.isPlayable)
        let video = try await asset.loadTracks(withMediaType: .video)
        guard playable, !video.isEmpty else { throw URLError(.cannotDecodeContentData) }
        guard (try? SharedLinks.entry(id).state) == .downloading else {
          try? FileManager.default.removeItem(at: staging)
          return
        }
        let destination = try SharedLinks.file(id, suffix: "mp4")
        try FileManager.default.moveItem(at: staging, to: destination)
        finish(.saved)
      } catch {
        try? FileManager.default.removeItem(at: staging)
        finish(.failed)
      }
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    Self.appTasks.removeValue(forKey: id)
    if error != nil {
      finish(.failed)
    }
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    verification.notify(queue: .main) {
      Self.appDownloads.removeValue(forKey: self.id)
      session.finishTasksAndInvalidate()
      self.completion?()
      self.completion = nil
    }
  }

  private func finish(_ state: SharedLinks.Entry.State) {
    do {
      var entry = try SharedLinks.entry(id)
      guard entry.state == .downloading else { return }
      entry.state = state
      entry.progress = nil
      try SharedLinks.save(entry)
      Self.didChange?()
    } catch {
      NSLog("ClipShare could not update a download: %@", error.localizedDescription)
    }
  }
}
