import Darwin
import Foundation

enum SharedLinks {
  static let appGroup = "group.com.adesmith001.clipshare"

  struct Entry: Codable {
    enum State: String, Codable {
      case pending, downloading, saved, failed, cancelled
    }

    let id: String
    let url: String
    var state: State
    var progress: Double? = nil
    var imageExtension: String? = nil
    var title: String? = nil
    var slot: Int? = nil
    var position: String? = nil

    var channelValue: [String: Any] {
      var value: [String: Any] = [
        "id": id, "url": url, "state": state.rawValue,
        "canCancel": state == .downloading && BackgroundDownloads.canCancel(id),
        "canRetry": state == .failed || state == .cancelled,
        "canExport": state == .saved,
      ]
      if let progress { value["progress"] = progress }
      if imageExtension != nil { value["isImage"] = true }
      if let title { value["title"] = title }
      if let slot { value["slot"] = slot }
      if let position { value["position"] = position }
      return value
    }
  }

  static func webURL(_ url: URL) -> URL? {
    guard let scheme = url.scheme?.lowercased(),
          scheme == "https" || scheme == "http",
          let host = url.host, !host.isEmpty,
          url.user == nil, url.password == nil
    else { return nil }
    return url
  }

  static func isDirectVideo(_ url: URL) -> Bool {
    webURL(url) != nil && url.scheme?.lowercased() == "https" &&
      url.pathExtension.lowercased() == "mp4"
  }

  static func imageExtension(_ url: URL) -> String? {
    guard webURL(url) != nil, url.scheme?.lowercased() == "https" else { return nil }
    switch url.pathExtension.lowercased() {
    case "jpg", "jpeg": return "jpg"
    case "png": return "png"
    case "webp": return "webp"
    default: return nil
    }
  }

  static func isResolvedVideo(_ url: URL) -> Bool {
    if isDirectVideo(url) { return true }
    guard webURL(url) != nil, url.scheme == "https",
          url.host?.hasSuffix(".googlevideo.com") == true,
          url.path == "/videoplayback"
    else { return false }
    return URLComponents(url: url, resolvingAgainstBaseURL: false)?
      .queryItems?.contains { $0.name == "mime" && $0.value == "video/mp4" } == true
  }

  static func downloadKey(_ url: URL) -> String {
    guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else { return url.absoluteString }
    let scheme = parts.scheme?.lowercased()
    let host = parts.host?.lowercased()
    parts.scheme = scheme
    parts.host = host
    parts.fragment = nil
    return parts.string ?? url.absoluteString
  }

  static func withQueueLock<T>(_ work: () throws -> T) throws -> T {
    let directory = try inbox()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let descriptor = open(
      directory.appendingPathComponent(".queue-lock").path,
      O_CREAT | O_RDWR, mode_t(S_IRUSR | S_IWUSR)
    )
    guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
    defer { close(descriptor) }
    guard flock(descriptor, LOCK_EX) == 0 else { throw CocoaError(.fileWriteUnknown) }
    return try work()
  }

  static func enqueue(
    _ url: URL, state: Entry.State = .pending, imageExtension: String? = nil, title: String? = nil,
    slot: Int? = nil, position: String? = nil
  ) throws -> Entry {
    let id = String(format: "%020.0f", Date().timeIntervalSince1970 * 1_000) + "-" + UUID().uuidString
    let entry = Entry(
      id: id, url: url.absoluteString, state: state, imageExtension: imageExtension, title: title,
      slot: slot, position: position
    )
    try save(entry)
    return entry
  }

  static func entries() throws -> [Entry] {
    let directory = try inbox()
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    return try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
    )
      .compactMap { file -> Entry? in
        switch file.pathExtension {
        case "json":
          return try JSONDecoder().decode(Entry.self, from: Data(contentsOf: file))
        case "url":
          return try Entry(
            id: file.deletingPathExtension().lastPathComponent,
            url: String(contentsOf: file, encoding: .utf8),
            state: .pending
          )
        default:
          return nil
        }
      }
      .sorted { $0.id > $1.id }
  }

  static func entry(_ id: String) throws -> Entry {
    try JSONDecoder().decode(Entry.self, from: Data(contentsOf: file(id, suffix: "json")))
  }

  static func save(_ entry: Entry) throws {
    let destination = try file(entry.id, suffix: "json")
    try FileManager.default.createDirectory(
      at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try JSONEncoder().encode(entry).write(to: destination, options: .atomic)
  }

  static func file(_ id: String, suffix: String) throws -> URL {
    guard id.range(of: "^[0-9]{20}-[0-9A-Fa-f-]{36}$", options: .regularExpression) != nil
    else { throw CocoaError(.fileReadInvalidFileName) }
    return try inbox().appendingPathComponent(id).appendingPathExtension(suffix)
  }

  private static func inbox() throws -> URL {
    guard let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroup
    ) else { throw CocoaError(.fileNoSuchFile) }
    return container.appendingPathComponent("SharedLinks", isDirectory: true)
  }
}
