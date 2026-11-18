import Foundation

// Reads only page-provided JSON. Authentication stays entirely in WKWebView.
enum InstagramResolver {
  static let pageJSONScript = """
    (() => {
      const result = []; let total = 0;
      for (const node of document.querySelectorAll('script[type="application/json"]')) {
        const text = node.textContent || '';
        if (text.length > 6000000 || !/"(?:xig_polaris_media|shortcode_media|carousel_media|video_versions|video_url|image_versions2|edge_sidecar_to_children)"/.test(text)) continue;
        if (total + text.length > 8000000 || result.length >= 12) break;
        result.push(text); total += text.length;
      }
      return result;
    })()
    """

  struct Media {
    let url: URL
    let slot: Int
    let position: String?
  }

  struct Post {
    let title: String?
    let media: [Media]
    let total: Int
  }

  static func shortcode(_ url: URL) -> String? {
    guard let host = url.host?.lowercased(), ["instagram.com", "www.instagram.com", "m.instagram.com"].contains(host) else { return nil }
    let path = url.pathComponents.filter { $0 != "/" }
    let index: Int
    if path.count >= 2, ["p", "reel", "reels", "tv"].contains(path[0]) { index = 1 }
    else if path.count >= 3, path[0] == "share", ["p", "reel", "reels", "tv"].contains(path[1]) { index = 2 }
    else { return nil }
    return path[index].range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil ? path[index] : nil
  }

  static func parse(_ scripts: [String], shortcode: String) -> Post? {
    for script in scripts {
      guard script.utf8.count < 8_000_000, let data = script.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) else { continue }
      var remaining = 100_000
      if let media = find(root, shortcode: shortcode, depth: 0, remaining: &remaining) {
        return post(media)
      }
    }
    return nil
  }

  private static func find(_ value: Any, shortcode: String, depth: Int, remaining: inout Int) -> [String: Any]? {
    guard depth < 80, remaining > 0 else { return nil }
    remaining -= 1
    if let object = value as? [String: Any] {
      if (object["shortcode"] as? String ?? object["code"] as? String) == shortcode,
         object["video_url"] != nil || object["display_url"] != nil || object["image_versions2"] != nil ||
          object["video_versions"] != nil || object["edge_sidecar_to_children"] != nil || object["carousel_media"] != nil {
        return object
      }
      // Prefer the requested post shape over recommendation / related-media trees.
      for key in ["xig_polaris_shortcode_web_info", "xig_polaris_media", "shortcode_media", "items"] {
        if let child = object[key], let match = find(child, shortcode: shortcode, depth: depth + 1, remaining: &remaining) { return match }
      }
      for child in object.values {
        if let match = find(child, shortcode: shortcode, depth: depth + 1, remaining: &remaining) { return match }
      }
    } else if let array = value as? [Any] {
      for child in array {
        if let match = find(child, shortcode: shortcode, depth: depth + 1, remaining: &remaining) { return match }
      }
    }
    return nil
  }

  private static func post(_ object: [String: Any]) -> Post {
    let edgeCaption = ((object["edge_media_to_caption"] as? [String: Any])?["edges"] as? [[String: Any]])?.first?["node"] as? [String: Any]
    let title = (object["caption"] as? [String: Any])?["text"] as? String ??
      edgeCaption?["text"] as? String ?? object["title"] as? String
    let sidecar = ((object["edge_sidecar_to_children"] as? [String: Any])?["edges"] as? [Any])?
      .map { ($0 as? [String: Any])?["node"] as? [String: Any] ?? [:] }
    let carousel = (object["carousel_media"] as? [Any])?.map { $0 as? [String: Any] ?? [:] }
    let missingCarousel = object["media_type"] as? Int == 8 || object["__typename"] as? String == "GraphSidecar"
    let slides = carousel ?? sidecar ?? (missingCarousel ? [] : [object])
    let media = slides.enumerated().compactMap { index, slide -> Media? in
      guard let url = mediaURL(slide) else { return nil }
      return Media(url: url, slot: index, position: slides.count > 1 ? "\(index + 1)/\(slides.count)" : nil)
    }
    return Post(title: title.map { String($0.prefix(500)) }, media: media, total: slides.count)
  }

  private static func mediaURL(_ object: [String: Any]) -> URL? {
    let videos = object["video_versions"] as? [[String: Any]] ?? []
    let isVideo = object["is_video"] as? Bool == true || object["media_type"] as? Int == 2 ||
      object["video_url"] != nil || !videos.isEmpty
    if isVideo {
      return allowedURL(object["video_url"] as? String, video: true) ?? best(videos, video: true)
    }
    let candidates = (object["image_versions2"] as? [String: Any])?["candidates"] as? [[String: Any]] ??
      object["display_resources"] as? [[String: Any]] ?? []
    return best(candidates, video: false) ?? allowedURL(object["display_url"] as? String, video: false)
  }

  private static func best(_ candidates: [[String: Any]], video: Bool) -> URL? {
    candidates.sorted {
      (Double($0["width"] as? Int ?? $0["config_width"] as? Int ?? 0) * Double($0["height"] as? Int ?? $0["config_height"] as? Int ?? 0)) >
      (Double($1["width"] as? Int ?? $1["config_width"] as? Int ?? 0) * Double($1["height"] as? Int ?? $1["config_height"] as? Int ?? 0))
    }.compactMap { allowedURL($0["url"] as? String ?? $0["src"] as? String, video: video) }.first
  }

  private static func allowedURL(_ value: String?, video: Bool) -> URL? {
    guard let value, let url = URL(string: value), url.scheme?.lowercased() == "https",
          url.user == nil, url.password == nil, let host = url.host?.lowercased(),
          host == "cdninstagram.com" || host.hasSuffix(".cdninstagram.com") ||
          host == "fbcdn.net" || host.hasSuffix(".fbcdn.net"),
          (video ? url.pathExtension.lowercased() == "mp4" : ["jpg", "jpeg", "png", "webp"].contains(url.pathExtension.lowercased()))
    else { return nil }
    return url
  }
}
