import AVFoundation
import Foundation

final class BackgroundDownloads: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  static let sessionPrefix = "com.adesmith001.clipshare.share-download."
  static var didChange: (() -> Void)?

  private let id: String
  private let completion: (() -> Void)?
  private let verification = DispatchGroup()

  private init(id: String, completion: (() -> Void)? = nil) {
    self.id = id
    self.completion = completion
  }

  private func makeSession() -> URLSession {
    let configuration = URLSessionConfiguration.background(
      withIdentifier: Self.sessionPrefix + id
    )
    configuration.sharedContainerIdentifier = SharedLinks.appGroup
    return URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
  }

  static func start(_ url: URL) throws {
    let entry = try SharedLinks.enqueue(url, state: .downloading)
    let session = BackgroundDownloads(id: entry.id).makeSession()
    session.downloadTask(with: url).resume()
  }

  static func reconnect(identifier: String, completion: @escaping () -> Void) {
    let id = String(identifier.dropFirst(sessionPrefix.count))
    _ = BackgroundDownloads(id: id, completion: completion).makeSession()
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL
  ) {
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
    if error != nil {
      finish(.failed)
    }
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    verification.notify(queue: .main) { [completion] in
      session.finishTasksAndInvalidate()
      completion?()
    }
  }

  private func finish(_ state: SharedLinks.Entry.State) {
    do {
      var entry = try SharedLinks.entry(id)
      entry.state = state
      try SharedLinks.save(entry)
      Self.didChange?()
    } catch {
      NSLog("ClipShare could not update a download: %@", error.localizedDescription)
    }
  }
}
