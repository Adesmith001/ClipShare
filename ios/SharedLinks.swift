import Foundation

enum SharedLinks {
  static func webURL(_ url: URL) -> URL? {
    guard let scheme = url.scheme?.lowercased(),
          scheme == "https" || scheme == "http",
          let host = url.host, !host.isEmpty,
          url.user == nil, url.password == nil
    else { return nil }
    return url
  }

  static func enqueue(_ url: URL) throws {
    let directory = try inbox()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let id = String(format: "%020.0f", Date().timeIntervalSince1970 * 1_000) + "-" + UUID().uuidString
    let entry = directory.appendingPathComponent(id).appendingPathExtension("url")
    try Data(url.absoluteString.utf8).write(to: entry, options: .atomic)
  }

  static func pending() throws -> [String] {
    let directory = try inbox()
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    return try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
    )
      .filter { $0.pathExtension == "url" }
      .sorted { $0.lastPathComponent > $1.lastPathComponent }
      .map { try String(contentsOf: $0, encoding: .utf8) }
  }

  private static func inbox() throws -> URL {
    guard let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: "group.com.adesmith001.clipshare"
    ) else { throw CocoaError(.fileNoSuchFile) }
    return container.appendingPathComponent("SharedLinks", isDirectory: true)
  }
}
