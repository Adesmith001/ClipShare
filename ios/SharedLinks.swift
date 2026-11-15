import Foundation

enum SharedLinks {
  static let appGroup = "group.com.adesmith001.clipshare"

  struct Entry: Codable {
    enum State: String, Codable {
      case pending, downloading, saved, failed
    }

    let id: String
    let url: String
    var state: State

    var channelValue: [String: String] {
      ["id": id, "url": url, "state": state.rawValue]
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

  static func enqueue(_ url: URL, state: Entry.State = .pending) throws -> Entry {
    let id = String(format: "%020.0f", Date().timeIntervalSince1970 * 1_000) + "-" + UUID().uuidString
    let entry = Entry(id: id, url: url.absoluteString, state: state)
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
