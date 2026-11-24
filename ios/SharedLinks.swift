import Darwin
import Foundation

enum SharedLinks {
  #if STORE_BETA
  static let appGroup = "group.com.adesmith001.clipshare.beta"
  #else
  static let appGroup = "group.com.adesmith001.clipshare"
  #endif

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
    var folder: String? = nil
    var sizeBytes: Int64? = nil
    var error: String? = nil
    var sessionIdentifier: String? = nil
    var aliases: [String]? = nil

    var channelValue: [String: Any] {
      var value: [String: Any] = [
        "id": id, "url": url, "state": state.rawValue,
        "canCancel": state == .downloading && BackgroundDownloads.canCancel(id),
        "canRetry": state == .failed || state == .cancelled,
        "canExport": state == .saved,
        "folder": folder ?? "", "sizeBytes": sizeBytes ?? 0,
      ]
      if let progress { value["progress"] = progress }
      if imageExtension != nil { value["isImage"] = true }
      if let title { value["title"] = title }
      if let slot { value["slot"] = slot }
      if let position { value["position"] = position }
      if state == .saved, let file = try? SharedLinks.file(id, suffix: imageExtension ?? "mp4") {
        value["sizeBytes"] = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
      }
      if let error, ["network", "timeout", "storage_unavailable", "http_error", "invalid_media", "interrupted", "file_missing"].contains(error) { value["error"] = error }
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
    if isTikTokMedia(url) { return true }
    guard webURL(url) != nil, url.scheme == "https",
          url.host?.hasSuffix(".googlevideo.com") == true,
          url.path == "/videoplayback"
    else { return false }
    return URLComponents(url: url, resolvingAgainstBaseURL: false)?
      .queryItems?.contains { $0.name == "mime" && $0.value == "video/mp4" } == true
  }

  static func tikTokVideoID(_ url: URL) -> String? {
    guard ["tiktok.com", "www.tiktok.com", "m.tiktok.com"].contains(url.host?.lowercased() ?? "") else { return nil }
    for pattern in [#"^/@[\w.-]+/video/([0-9]+)/?$"#, #"^/v/([0-9]+)\.html/?$"#] {
      let regex = try! NSRegularExpression(pattern: pattern)
      if let match = regex.firstMatch(in: url.path, range: NSRange(url.path.startIndex..., in: url.path)),
         let range = Range(match.range(at: 1), in: url.path) { return String(url.path[range]) }
    }
    return nil
  }

  static func isTikTokLink(_ url: URL) -> Bool {
    guard webURL(url) != nil, url.scheme == "https" else { return false }
    if tikTokVideoID(url) != nil { return true }
    let host = url.host?.lowercased() ?? ""
    if ["vm.tiktok.com", "vt.tiktok.com"].contains(host) {
      return url.path.range(of: #"^/[\w-]+/?$"#, options: .regularExpression) != nil
    }
    return ["tiktok.com", "www.tiktok.com", "m.tiktok.com"].contains(host) &&
      url.path.range(of: #"^/t/[\w-]+/?$"#, options: .regularExpression) != nil
  }

  static func isTikTokMedia(_ url: URL) -> Bool {
    guard webURL(url) != nil, url.scheme == "https", let host = url.host?.lowercased() else { return false }
    if ["tikwm.com", "www.tikwm.com"].contains(host) { return url.path.hasPrefix("/video/") }
    return ["tiktokcdn.com", "tiktokcdn-us.com", "tiktokcdn-eu.com", "tiktokv.com"]
      .contains(where: { host == $0 || host.hasSuffix("." + $0) }) && url.path.contains("/video/")
  }

  static func downloadKey(_ url: URL) -> String {
    if let canonical = canonicalSource(url), canonical != url { return canonical.absoluteString }
    guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else { return url.absoluteString }
    let scheme = parts.scheme?.lowercased()
    let host = parts.host?.lowercased()
    parts.scheme = scheme
    parts.host = host
    parts.fragment = nil
    return parts.string ?? url.absoluteString
  }

  static func canonicalSource(_ url: URL) -> URL? {
    guard webURL(url) != nil, let host = url.host?.lowercased() else { return nil }
    if isTikTokLink(url) {
      if let id = tikTokVideoID(url) { return URL(string: "https://www.tiktok.com/@_/video/\(id)") }
      var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
      parts?.query = nil
      parts?.fragment = nil
      parts?.path = url.path.hasSuffix("/") ? String(url.path.dropLast()) : url.path
      return parts?.url
    }
    let path = url.pathComponents.filter { $0 != "/" }
    let codePattern = "^[A-Za-z0-9_-]+$"
    func valid(_ code: String) -> Bool { code.range(of: codePattern, options: .regularExpression) != nil }
    if ["instagram.com", "www.instagram.com", "m.instagram.com"].contains(host) {
      let index: Int
      if path.count >= 2, ["p", "reel", "reels", "tv"].contains(path[0]) { index = 1 }
      else if path.count >= 3, path[0] == "share", ["p", "reel", "reels", "tv"].contains(path[1]) {
        return valid(path[2]) ? URL(string: "https://www.instagram.com/share/\(path[1])/\(path[2])/") : nil
      }
      else { return nil }
      return valid(path[index]) ? URL(string: "https://www.instagram.com/p/\(path[index])/") : nil
    }
    if ["twitter.com", "www.twitter.com", "mobile.twitter.com", "x.com", "www.x.com", "mobile.x.com"].contains(host),
       let match = url.path.range(of: "^/(?:i/web|[^/]+)/status/[0-9]+(?:/|$)", options: .regularExpression) {
      let components = url.path[match].split(separator: "/")
      if let status = components.firstIndex(of: "status"), components.indices.contains(status + 1) {
        return URL(string: "https://x.com/i/web/status/\(components[status + 1])")
      }
    }
    if host == "pin.it", let pin = path.first, valid(pin) { return URL(string: "https://pin.it/\(pin)") }
    if host == "pinterest.com" || host.hasSuffix(".pinterest.com"),
       path.count == 2, path[0] == "pin",
       let pin = path[1].components(separatedBy: "--").last,
       !pin.isEmpty, pin.range(of: "^[0-9]+$", options: .regularExpression) != nil {
      return URL(string: "https://www.pinterest.com/pin/\(pin)/")
    }
    var youtubeID: String?
    if host == "youtu.be" { youtubeID = path.first }
    else if ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"].contains(host) {
      if path.first == "watch" { youtubeID = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value }
      else if path.count >= 2, ["shorts", "live"].contains(path[0]) { youtubeID = path[1] }
    }
    if let id = youtubeID, id.count == 11, valid(id) { return URL(string: "https://www.youtube.com/watch?v=\(id)") }
    if isDirectVideo(url) || imageExtension(url) != nil {
      var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
      parts?.fragment = nil
      return parts?.url
    }
    return nil
  }

  static func enqueuePending(_ url: URL) throws -> Bool {
    guard let source = canonicalSource(url) else { throw URLError(.unsupportedURL) }
    return try withQueueLock {
      if try entries().contains(where: {
        [.pending, .downloading, .saved].contains($0.state) &&
          (URL(string: $0.url).map(downloadKey) == downloadKey(source) || ($0.aliases ?? []).contains(downloadKey(source)))
      }) { return false }
      _ = try enqueue(source)
      return true
    }
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
          // Protected-data / I/O failures are not evidence of corrupt JSON.
          guard let data = try? Data(contentsOf: file) else { return nil }
          do {
            let entry = try JSONDecoder().decode(Entry.self, from: data)
            guard try self.file(entry.id, suffix: "json").lastPathComponent == file.lastPathComponent,
                  entry.imageExtension == nil || ["jpg", "png", "webp"].contains(entry.imageExtension!),
                  webURL(URL(string: entry.url) ?? URL(fileURLWithPath: "/")) != nil
            else { throw CocoaError(.fileReadCorruptFile) }
            return entry
          } catch {
            try? quarantine(file)
            return nil
          }
        case "url":
          if FileManager.default.fileExists(atPath: file.deletingPathExtension().appendingPathExtension("json").path) { return nil }
          guard let data = try? Data(contentsOf: file) else { return nil }
          guard let source = String(data: data, encoding: .utf8),
                let url = URL(string: source), webURL(url) != nil,
                (try? self.file(file.deletingPathExtension().lastPathComponent, suffix: "url")) != nil
          else { try? quarantine(file); return nil }
          return Entry(
            id: file.deletingPathExtension().lastPathComponent,
            url: source,
            state: .pending
          )
        default:
          return nil
        }
      }
      .sorted { $0.id > $1.id }
  }

  static func entry(_ id: String) throws -> Entry {
    if let data = try? Data(contentsOf: file(id, suffix: "json")) {
      return try JSONDecoder().decode(Entry.self, from: data)
    }
    return Entry(id: id, url: try String(contentsOf: file(id, suffix: "url"), encoding: .utf8), state: .pending)
  }

  private static func quarantine(_ file: URL) throws {
    let directory = file.deletingLastPathComponent().appendingPathComponent(".quarantine", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    // Keep the original bytes for recovery, but do not let one record hide healthy entries.
    do { try FileManager.default.moveItem(at: file, to: directory.appendingPathComponent(UUID().uuidString + "-" + file.lastPathComponent)) }
    catch { if FileManager.default.fileExists(atPath: file.path) { throw error } }
  }

  static func recoveredEntries() throws -> Int {
    let directory = try inbox().appendingPathComponent(".quarantine")
    return (try? FileManager.default.contentsOfDirectory(atPath: directory.path).count) ?? 0
  }

  static func storageBytes() throws -> Int64 {
    guard FileManager.default.fileExists(atPath: try inbox().path) else { return 0 }
    let files = try FileManager.default.contentsOfDirectory(at: inbox(), includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles)
    return files.filter { ["mp4", "jpg", "png", "webp"].contains($0.pathExtension) }
      .reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
  }

  static func validFolderName(_ raw: String) -> String? {
    let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, name.count <= 60,
          !["all downloads", "unfiled"].contains(name.lowercased()),
          !name.contains("/"), !name.contains("\\"),
          name.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
    return name
  }

  static func folders() throws -> [String] {
    let file = try inbox().appendingPathComponent(".folders.json")
    guard FileManager.default.fileExists(atPath: file.path) else { return [] }
    let data = try Data(contentsOf: file)
    do { return try JSONDecoder().decode([String].self, from: data) }
    catch {
      try? quarantine(file)
      // Recover names already assigned to healthy entries after registry corruption.
      let recovered = Array(Set(try entries().compactMap { $0.folder.flatMap(validFolderName) }))
      try? saveFolders(recovered)
      return recovered
    }
  }

  private static func saveFolders(_ names: [String]) throws {
    try JSONEncoder().encode(names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
      .write(to: inbox().appendingPathComponent(".folders.json"), options: .atomic)
  }

  static func createFolder(_ raw: String) throws -> Bool {
    guard let name = validFolderName(raw) else { return false }
    return try withQueueLock {
      var names = try folders()
      guard !names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { return false }
      names.append(name)
      try saveFolders(names)
      return true
    }
  }

  static func renameFolder(_ from: String, to raw: String?) throws -> Bool {
    guard raw == nil || validFolderName(raw!) != nil else { return false }
    return try withQueueLock {
      var names = try folders()
      guard let index = names.firstIndex(of: from) else { return false }
      let to = raw.flatMap(validFolderName) ?? ""
      guard !names.enumerated().contains(where: { $0.offset != index && $0.element.caseInsensitiveCompare(to) == .orderedSame }) else { return false }
      let affected = try entries().filter { $0.folder == from }
      for var entry in affected { entry.folder = to; try save(entry) }
      if to.isEmpty { names.remove(at: index) } else { names[index] = to }
      try saveFolders(names)
      return true
    }
  }

  static func move(_ ids: [String], folder: String) throws -> Bool {
    try withQueueLock {
      let names = try folders()
      guard folder.isEmpty || names.contains(folder) else { return false }
      let entries = try ids.map(entry)
      for var entry in entries { entry.folder = folder; try save(entry) }
      return true
    }
  }

  static func removeFiles(_ id: String) throws {
    for suffix in ["mp4", "jpg", "png", "webp", "staging.mp4", "url", "json"] {
      let url = try file(id, suffix: suffix)
      if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
  }

  static func save(_ entry: Entry) throws {
    let destination = try file(entry.id, suffix: "json")
    try FileManager.default.createDirectory(
      at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try JSONEncoder().encode(entry).write(to: destination, options: .atomic)
    let legacy = try file(entry.id, suffix: "url")
    if FileManager.default.fileExists(atPath: legacy.path) { try FileManager.default.removeItem(at: legacy) }
  }

  static func file(_ id: String, suffix: String) throws -> URL {
    guard id.range(of: "^[0-9]{20}-[0-9A-Fa-f-]{36}$", options: .regularExpression) != nil
      && ["json", "url", "mp4", "jpg", "png", "webp", "staging.mp4"].contains(suffix)
    else { throw CocoaError(.fileReadInvalidFileName) }
    return try inbox().appendingPathComponent(id).appendingPathExtension(suffix)
  }

  private static func inbox() throws -> URL {
    if let testDirectory { return testDirectory }
    guard let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroup
    ) else { throw CocoaError(.fileNoSuchFile) }
    return container.appendingPathComponent("SharedLinks", isDirectory: true)
  }
  // RunnerTests uses an isolated directory; production always uses the App Group.
  static var testDirectory: URL?
}
