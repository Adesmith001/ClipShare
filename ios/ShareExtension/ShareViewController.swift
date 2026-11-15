import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
  private let message = UILabel()
  private let saveButton = UIButton(type: .system)
  private var sharedURL: URL?

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

    let stack = UIStackView(arrangedSubviews: [message, saveButton, cancel])
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
          sharedURL = url
          message.text = url.absoluteString
          message.lineBreakMode = .byTruncatingMiddle
          message.numberOfLines = 3
          saveButton.setTitle(SharedLinks.isDirectVideo(url) ? "Download" : "Add to ClipShare", for: .normal)
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
    do {
      if SharedLinks.isDirectVideo(sharedURL) {
        guard try BackgroundDownloads.start(sharedURL) else {
          message.text = "This video is already in Downloads."
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

  @objc private func close() {
    extensionContext?.completeRequest(returningItems: nil)
  }
}
