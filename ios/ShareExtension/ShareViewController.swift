import UIKit
import UniformTypeIdentifiers
import WebKit

final class ShareViewController: UIViewController, WKNavigationDelegate {
  private enum InstagramState: Equatable {
    case idle
    case checking
    case signingIn
    case retrySharedLink
    case resolving
    case queued
    case failed
  }

  private let message = UILabel()
  private let saveButton = UIButton(type: .system)
  private let disconnectButton = UIButton(type: .system)
  private let webView: WKWebView = {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .default()
    return WKWebView(frame: .zero, configuration: configuration)
  }()
  private var webViewHeight: NSLayoutConstraint!
  private var sharedURL: URL?
  private var instagramState = InstagramState.idle
  private var webLoadTimeout: DispatchWorkItem?
  private var resolutionAttempt = 0
  private var navigationGeneration = 0
  private var responseStatus = 200
  private var desktopReelCode: String?

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

    disconnectButton.setTitle("Disconnect Instagram", for: .normal)
    disconnectButton.addTarget(self, action: #selector(disconnectInstagram), for: .touchUpInside)
    disconnectButton.isHidden = true
    let scroll = UIScrollView()
    scroll.keyboardDismissMode = .interactive
    scroll.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(scroll)
    let stack = UIStackView(arrangedSubviews: [message, webView, saveButton, disconnectButton, cancel])
    stack.axis = .vertical
    stack.spacing = 16
    stack.translatesAutoresizingMaskIntoConstraints = false
    scroll.addSubview(stack)
    let safeArea = view.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
      scroll.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
      scroll.topAnchor.constraint(equalTo: safeArea.topAnchor),
      scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
      stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
      stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
      stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
      stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20),
      stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40),
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
          guard let normalizedURL = SharedLinks.canonicalSource(url) else { continue }
          if InstagramResolver.isReel(url), !normalizedURL.path.hasPrefix("/share/"),
             let code = InstagramResolver.shortcode(url) {
            sharedURL = URL(string: "https://www.instagram.com/reel/\(code)/")
          } else {
            sharedURL = normalizedURL
          }
          message.text = normalizedURL.host.map { "Ready to add media from \($0)." }
          message.lineBreakMode = .byTruncatingMiddle
          message.numberOfLines = 3
          let direct = SharedLinks.isDirectVideo(normalizedURL) ||
            SharedLinks.imageExtension(normalizedURL) != nil
          saveButton.setTitle(
            direct ? "Download" : (InstagramResolver.shortcode(normalizedURL) == nil
              ? "Add to ClipShare"
              : "Continue with Instagram"),
            for: .normal
          )
          saveButton.isEnabled = true
          return
        }
      }
    }
    message.text = "Share a supported Instagram, X, Pinterest, YouTube, TikTok or direct media link."
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
    if InstagramResolver.shortcode(sharedURL) != nil {
      switch instagramState {
      case .idle:
        showInstagramPage(sharedURL)
      case .retrySharedLink, .signingIn:
        showInstagramPage(sharedURL)
      case .failed:
        showInstagramPage(sharedURL)
      case .checking, .resolving, .queued:
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
        guard try SharedLinks.enqueuePending(sharedURL) else {
          message.text = "This link is already waiting in Downloads."
          saveButton.isEnabled = false
          return
        }
      }
      close()
    } catch {
      message.text = "Couldn’t add the link. Try again."
    }
  }

  private func showInstagramPage(_ url: URL, desktopReel: Bool = false) {
    navigationGeneration += 1
    resolutionAttempt = 0
    responseStatus = 200
    desktopReelCode = desktopReel ? InstagramResolver.shortcode(url) : nil
    instagramState = .checking
    webLoadTimeout?.cancel()
    saveButton.isEnabled = false
    saveButton.setTitle("Checking Instagram…", for: .normal)
    message.text = "Opening the shared post in Instagram…"
    webView.isHidden = false
    disconnectButton.isHidden = false
    webViewHeight.constant = max(240, min(600, view.safeAreaLayoutGuide.layoutFrame.height * 0.65))
    UIView.animate(withDuration: 0.2) { self.view.layoutIfNeeded() }
    NSLog("ClipShare InstagramShare starting page load")
    webView.load(URLRequest(url: url))
    let timeout = DispatchWorkItem { [weak self] in
      guard let self else { return }
      guard self.instagramState == .checking else { return }
      NSLog("ClipShare InstagramShare page load timed out")
      self.webView.stopLoading()
      self.instagramState = .failed
      self.message.text = "Instagram did not finish loading. Check your connection and retry."
      self.saveButton.setTitle("Retry Instagram", for: .normal)
      self.saveButton.isEnabled = true
    }
    webLoadTimeout = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(20), execute: timeout)
  }

  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    let host = webView.url?.host?.lowercased() ?? "unknown"
    NSLog("ClipShare InstagramShare navigation started host=%@", host)
  }

  func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
    let host = webView.url?.host?.lowercased() ?? "unknown"
    NSLog("ClipShare InstagramShare navigation committed host=%@", host)
  }

  func webView(
    _ webView: WKWebView,
    didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    reportInstagramLoadFailure(error)
  }

  func webView(
    _ webView: WKWebView,
    didFail navigation: WKNavigation!,
    withError error: Error
  ) {
    reportInstagramLoadFailure(error)
  }

  private func reportInstagramLoadFailure(_ error: Error) {
    let failure = error as NSError
    NSLog(
      "ClipShare InstagramShare navigation failed domain=%@ code=%ld",
      failure.domain,
      failure.code
    )
    webLoadTimeout?.cancel()
    guard failure.code != NSURLErrorCancelled,
          instagramState == .checking || instagramState == .signingIn || instagramState == .resolving else { return }
    instagramState = .failed
    message.text = "Instagram could not load. Check your connection and retry."
    saveButton.setTitle("Retry Instagram", for: .normal)
    saveButton.isEnabled = true
  }

  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationAction: WKNavigationAction,
    preferences: WKWebpagePreferences,
    decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
  ) {
    guard let url = navigationAction.request.url,
          let host = url.host?.lowercased()
    else {
      decisionHandler(.cancel, preferences)
      return
    }
    let instagramHost = host == "instagram.com" || host.hasSuffix(".instagram.com")
    let facebookHost = host == "facebook.com" || host.hasSuffix(".facebook.com")
    guard url.scheme?.lowercased() == "https", instagramHost || facebookHost else {
      NSLog("ClipShare InstagramShare blocked navigation scheme=%@ host=%@", url.scheme ?? "unknown", host)
      decisionHandler(.cancel, preferences)
      return
    }
    NSLog("ClipShare InstagramShare allowed navigation scheme=%@ host=%@", url.scheme ?? "unknown", host)
    if navigationAction.targetFrame?.isMainFrame != false && instagramHost && Self.isInstagramLogin(url) {
      instagramState = .signingIn
      message.text = "Sign in to Instagram here. ClipShare does not see your password."
      saveButton.setTitle("Continue to shared post after sign-in", for: .normal)
      saveButton.isEnabled = true
    }
    if let desktopReelCode, navigationAction.targetFrame?.isMainFrame != false,
       InstagramResolver.shortcode(url) == desktopReelCode {
      preferences.preferredContentMode = .desktop
    }
    decisionHandler(.allow, preferences)
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    guard let url = webView.url else { return }
    webLoadTimeout?.cancel()
    NSLog("ClipShare InstagramShare navigation finished host=%@", url.host?.lowercased() ?? "unknown")
    if Self.isInstagramChallenge(url) {
      instagramState = .signingIn
      message.text = "Complete Instagram’s security check here, then continue to the shared post."
      saveButton.setTitle("Continue to shared post", for: .normal)
      saveButton.isEnabled = true
      instagramState = .retrySharedLink
      return
    }
    if Self.isInstagramLogin(url) {
      instagramState = .signingIn
      message.text = "Sign in to Instagram here. ClipShare does not see your password."
      saveButton.setTitle("Continue to shared post after sign-in", for: .normal)
      saveButton.isEnabled = true
      return
    }
    switch instagramState {
    case .signingIn:
      if let sharedURL { showInstagramPage(sharedURL) }
    case .checking:
      if responseStatus == 404 || responseStatus == 410 {
        failInstagram("This Instagram post is unavailable or you do not have access to it.")
      } else if responseStatus >= 400 {
        failInstagram("Instagram could not load this post. Retry after checking your connection or account.")
      } else {
        instagramState = .resolving
        message.text = "Looking for media in the shared post…"
        resolveInstagram(generation: navigationGeneration)
      }
    case .retrySharedLink:
      if let sharedURL { showInstagramPage(sharedURL) }
    case .idle, .resolving, .queued, .failed:
      break
    }
  }

  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationResponse: WKNavigationResponse,
    decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
  ) {
    if let response = navigationResponse.response as? HTTPURLResponse {
      if navigationResponse.isForMainFrame { responseStatus = response.statusCode }
      NSLog(
        "ClipShare InstagramShare response status=%ld host=%@",
        response.statusCode,
        response.url?.host?.lowercased() ?? "unknown"
      )
    }
    decisionHandler(.allow)
  }

  @objc private func disconnectInstagram() {
    navigationGeneration += 1
    webLoadTimeout?.cancel()
    let store = WKWebsiteDataStore.default()
    let types = WKWebsiteDataStore.allWebsiteDataTypes()
    store.fetchDataRecords(ofTypes: types) { [weak self] records in
      let instagramRecords = records.filter {
        let domain = $0.displayName.lowercased()
        return domain == "instagram.com" || domain.hasSuffix(".instagram.com") ||
          domain == "facebook.com" || domain.hasSuffix(".facebook.com")
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

  private func failInstagram(_ text: String) {
    instagramState = .failed
    message.text = text
    saveButton.setTitle("Retry shared post", for: .normal)
    saveButton.isEnabled = true
  }

  private func resolveInstagram(generation: Int) {
    guard instagramState == .resolving, generation == navigationGeneration else { return }
    guard let sharedURL, let requestedCode = InstagramResolver.shortcode(sharedURL),
          let finalURL = webView.url, let finalCode = InstagramResolver.shortcode(finalURL) else {
      failInstagram("Open the shared post in Instagram, then retry.")
      return
    }
    let sharedAlias = sharedURL.path.hasPrefix("/share/")
    guard desktopReelCode.map({ $0 == finalCode }) ?? (sharedAlias || requestedCode == finalCode) else {
      failInstagram("Instagram opened a different post. Retry the original shared link.")
      return
    }
    let isReel = InstagramResolver.isReel(sharedURL) || InstagramResolver.isReel(finalURL)
    let needsReelPage = isReel && sharedAlias && finalURL.path.hasPrefix("/share/")
    webView.evaluateJavaScript(InstagramResolver.pageJSONScript) { [weak self] result, error in
      guard let self, generation == self.navigationGeneration, self.instagramState == .resolving else { return }
      if error != nil {
        self.failInstagram("Could not read the shared post. Check your connection and retry.")
        return
      }
      let pageData = result as? [String] ?? []
      // Some share aliases provide the real Reel URL in metadata without redirecting.
      let postURL = needsReelPage ? InstagramResolver.reelPage(pageData.first) : finalURL
      let postCode = postURL.flatMap(InstagramResolver.shortcode)
      guard let postURL, let code = postCode, let source = SharedLinks.canonicalSource(postURL),
            let post = InstagramResolver.parse(
              Array(pageData.dropFirst()), shortcode: code, reelMetadata: pageData.first, isReel: isReel
            ) else {
        self.resolutionAttempt += 1
        if self.resolutionAttempt < 5 {
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in self?.resolveInstagram(generation: generation) }
        } else if isReel, self.desktopReelCode == nil, let postCode,
                  let reelURL = URL(string: "https://www.instagram.com/reel/\(postCode)/") {
          self.showInstagramPage(reelURL, desktopReel: true)
        } else {
          self.failInstagram("This post could not be read. It may be unavailable, require sign-in, or use an unsupported Instagram format.")
        }
        return
      }
      guard !post.media.isEmpty else {
        self.failInstagram("This Instagram post has no supported photo or MP4 media.")
        return
      }
      var queued = 0
      var duplicates = 0
      var failed = post.total - post.media.count
      let chosenFolder: String
      do {
        let entries = try SharedLinks.entries()
        let key = SharedLinks.downloadKey(source)
        let aliasKey = SharedLinks.downloadKey(sharedURL)
        let pending = entries.first {
          guard $0.state == .pending, let url = URL(string: $0.url) else { return false }
          let pendingKey = SharedLinks.downloadKey(url)
          return pendingKey == key || pendingKey == aliasKey
        }
        let fallback = entries.first { URL(string: $0.url).map(SharedLinks.downloadKey) == key && !($0.folder ?? "").isEmpty }
        chosenFolder = pending.map { $0.folder ?? "" } ?? fallback?.folder ?? ""
      } catch {
        self.failInstagram("Couldn’t read Downloads. Check available storage and retry.")
        return
      }
      for media in post.media {
        do {
          if try BackgroundDownloads.start(media.url, source: source, title: post.title, slot: media.slot, position: media.position, sourceAlias: sharedURL, folder: chosenFolder) { queued += 1 }
          else { duplicates += 1 }
        } catch { failed += 1 }
      }
      guard queued + duplicates > 0 else {
        self.failInstagram("Couldn’t queue the post. Check available storage and retry.")
        return
      }
      self.instagramState = .queued
      self.saveButton.isEnabled = false
      self.message.text = "\(queued) queued · \(duplicates) already added" + (failed > 0 ? " · \(failed) unsupported or failed. Retry the shared post for missing items." : "")
      DispatchQueue.main.asyncAfter(deadline: .now() + (failed > 0 ? 2.5 : 0.8)) { [weak self] in
        guard let self, self.instagramState == .queued, generation == self.navigationGeneration else { return }
        self.close()
      }
    }
  }

  private static func isInstagramLogin(_ url: URL) -> Bool {
    url.host?.lowercased().hasSuffix("instagram.com") == true &&
      url.path.lowercased().contains("/accounts/login")
  }

  private static func isInstagramChallenge(_ url: URL) -> Bool {
    url.host?.lowercased().hasSuffix("instagram.com") == true &&
      ["/challenge", "/checkpoint", "/two_factor"].contains(where: { url.path.lowercased().contains($0) })
  }

  @objc private func close() {
    navigationGeneration += 1
    webLoadTimeout?.cancel()
    webView.stopLoading()
    extensionContext?.completeRequest(returningItems: nil)
  }
}
