import UIKit
import UniformTypeIdentifiers
import WebKit

final class ShareViewController: UIViewController, WKNavigationDelegate {
  private enum InstagramState {
    case idle
    case checking
    case signingIn
    case retrySharedLink
    case connected
  }

  private let message = UILabel()
  private let saveButton = UIButton(type: .system)
  private let webView: WKWebView = {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .default()
    return WKWebView(frame: .zero, configuration: configuration)
  }()
  private var webViewHeight: NSLayoutConstraint!
  private var sharedURL: URL?
  private var instagramState = InstagramState.idle

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    message.text = "Reading shared link…"
    message.numberOfLines = 0
    message.textAlignment = .center
    message.font = .preferredFont(forTextStyle: .body)
    message.adjustsFontForContentSizeCategory = true

    saveButton.configuration = .filled()
    saveButton.setTitle("Add to ClipShare", for: .normal)
    saveButton.isEnabled = false
    saveButton.addTarget(self, action: #selector(save), for: .touchUpInside)

    let cancel = UIButton(type: .system)
    cancel.setTitle("Cancel", for: .normal)
    cancel.addTarget(self, action: #selector(close), for: .touchUpInside)

    webView.navigationDelegate = self
    webView.isHidden = true
    webView.layer.cornerRadius = 12
    webView.clipsToBounds = true
    webView.translatesAutoresizingMaskIntoConstraints = false
    webViewHeight = webView.heightAnchor.constraint(equalToConstant: 0)
    webViewHeight.isActive = true

    let stack = UIStackView(arrangedSubviews: [message, webView, saveButton, cancel])
    stack.axis = .vertical
    stack.spacing = 16
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    let safeArea = view.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -24),
      stack.centerYAnchor.constraint(equalTo: safeArea.centerYAnchor),
      saveButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
      cancel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
    ])

    let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
    let providers = items.flatMap { $0.attachments ?? [] }
    Task { await loadLink(providers) }
  }

  private func loadLink(_ providers: [NSItemProvider]) async {
    for type in [UTType.url, .plainText] {
      for provider in providers where provider.hasItemConformingToTypeIdentifier(type.identifier) {
        let url: URL? = await withCheckedContinuation { continuation in
          provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, _ in
            continuation.resume(returning: Self.extractURL(item))
          }
        }
        if let url {
          let normalizedURL = Self.secureInstagramURL(url)
          sharedURL = normalizedURL
          message.text = normalizedURL.absoluteString
          message.lineBreakMode = .byTruncatingMiddle
          message.numberOfLines = 3
          let direct = SharedLinks.isDirectVideo(normalizedURL) ||
            SharedLinks.imageExtension(normalizedURL) != nil
          saveButton.setTitle(
            direct ? "Download" : (Self.instagramPostCode(normalizedURL) == nil
              ? "Add to ClipShare"
              : "Continue with Instagram"),
            for: .normal
          )
          saveButton.isEnabled = true
          return
        }
      }
    }
    message.text = "Share a web link to add it to ClipShare."
  }

  private nonisolated static func extractURL(_ item: (any NSSecureCoding)?) -> URL? {
    if let url = item as? URL { return SharedLinks.webURL(url) }
    guard let text = item as? String,
          let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    else { return nil }
    return detector.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))
      .compactMap { $0.url.flatMap(SharedLinks.webURL) }
      .first
  }

  @objc private func save() {
    guard let sharedURL else { return }
    if Self.instagramPostCode(sharedURL) != nil {
      switch instagramState {
      case .idle:
        showInstagramPage(sharedURL)
      case .retrySharedLink:
        showInstagramPage(sharedURL)
      case .connected:
        disconnectInstagram()
      case .checking, .signingIn:
        break
      }
      return
    }
    do {
      if SharedLinks.isDirectVideo(sharedURL) || SharedLinks.imageExtension(sharedURL) != nil {
        guard try BackgroundDownloads.start(sharedURL) else {
          message.text = "This item is already in Downloads."
          saveButton.isEnabled = false
          return
        }
      } else {
        _ = try SharedLinks.enqueue(sharedURL)
      }
      close()
    } catch {
      message.text = "Couldn’t add the link. Try again."
    }
  }

  private func showInstagramPage(_ url: URL) {
    instagramState = .checking
    saveButton.isEnabled = false
    saveButton.setTitle("Checking Instagram…", for: .normal)
    message.text = "Opening the shared post in Instagram's secure sign-in view…"
    webView.isHidden = false
    webViewHeight.constant = 380
    UIView.animate(withDuration: 0.2) { self.view.layoutIfNeeded() }
    webView.load(URLRequest(url: url))
  }

  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    guard let url = navigationAction.request.url,
          let host = url.host?.lowercased()
    else {
      decisionHandler(.cancel)
      return
    }
    let instagramHost = host == "instagram.com" || host.hasSuffix(".instagram.com")
    let facebookHost = host == "facebook.com" || host.hasSuffix(".facebook.com")
    guard url.scheme?.lowercased() == "https", instagramHost || facebookHost else {
      decisionHandler(.cancel)
      return
    }
    if instagramHost && Self.isInstagramLogin(url) {
      instagramState = .signingIn
      message.text = "Sign in to Instagram here. ClipShare does not see your password."
      saveButton.setTitle("Finish sign-in to continue", for: .normal)
      saveButton.isEnabled = false
    }
    decisionHandler(.allow)
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    guard let url = webView.url else { return }
    if Self.isInstagramLogin(url) || Self.isInstagramChallenge(url) {
      instagramState = .signingIn
      message.text = "Sign in to Instagram here. ClipShare does not see your password."
      saveButton.setTitle("Finish sign-in to continue", for: .normal)
      saveButton.isEnabled = false
      return
    }
    switch instagramState {
    case .signingIn:
      instagramState = .retrySharedLink
      message.text = "When Instagram sign-in is complete, continue to the shared post."
      saveButton.setTitle("Continue to shared post", for: .normal)
      saveButton.isEnabled = true
    case .checking:
      instagramState = .connected
      message.text = "Instagram is connected in ClipShare's share extension."
      saveButton.setTitle("Disconnect Instagram", for: .normal)
      saveButton.isEnabled = true
    case .idle, .retrySharedLink, .connected:
      break
    }
  }

  private func disconnectInstagram() {
    let store = WKWebsiteDataStore.default()
    let types = WKWebsiteDataStore.allWebsiteDataTypes()
    store.fetchDataRecords(ofTypes: types) { [weak self] records in
      let instagramRecords = records.filter {
        let domain = $0.displayName.lowercased()
        return domain == "instagram.com" || domain.hasSuffix(".instagram.com")
      }
      store.removeData(ofTypes: types, for: instagramRecords) {
        DispatchQueue.main.async {
          guard let self else { return }
          self.instagramState = .idle
          self.message.text = "Instagram has been disconnected from ClipShare."
          self.saveButton.setTitle("Connect Instagram", for: .normal)
          self.saveButton.isEnabled = true
          self.webView.stopLoading()
          self.webView.isHidden = true
          self.webViewHeight.constant = 0
          self.view.layoutIfNeeded()
        }
      }
    }
  }

  private static func instagramPostCode(_ url: URL) -> String? {
    guard let host = url.host?.lowercased(),
          host == "instagram.com" || host.hasSuffix(".instagram.com")
    else { return nil }
    let components = url.pathComponents.filter { $0 != "/" }
    let code: String?
    if let first = components.first, ["p", "reel", "reels", "tv"].contains(first) {
      code = components.dropFirst().first
    } else if components.count >= 3, components[0] == "share",
              ["p", "reel"].contains(components[1]) {
      code = components[2]
    } else {
      code = nil
    }
    guard let code, code.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil
    else { return nil }
    return code
  }

  private static func secureInstagramURL(_ url: URL) -> URL {
    guard let host = url.host?.lowercased(),
          host == "instagram.com" || host.hasSuffix(".instagram.com"),
          url.scheme?.lowercased() == "http",
          var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else { return url }
    components.scheme = "https"
    return components.url ?? url
  }

  private static func isInstagramLogin(_ url: URL) -> Bool {
    url.host?.lowercased().hasSuffix("instagram.com") == true &&
      url.path.lowercased().contains("/accounts/login")
  }

  private static func isInstagramChallenge(_ url: URL) -> Bool {
    url.host?.lowercased().hasSuffix("instagram.com") == true &&
      url.path.lowercased().contains("/challenge")
  }

  @objc private func close() {
    extensionContext?.completeRequest(returningItems: nil)
  }
}
