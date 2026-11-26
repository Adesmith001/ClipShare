import AVKit
import Flutter
import ImageIO
import Photos
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let preferences = FlutterMethodChannel(
      name: "clipshare/preferences",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    preferences.setMethodCallHandler { call, result in
      let defaults = UserDefaults.standard
      switch call.method {
      case "read":
        var values = defaults.dictionary(forKey: "clipshare_settings") ?? [:]
        if defaults.bool(forKey: "clipshare_tutorial_seen") {
          values["tutorialSeen"] = "true"
        }
        result(values)
      case "markTutorialSeen":
        defaults.set(true, forKey: "clipshare_tutorial_seen")
        result(true)
      case "write":
        let allowed: [String: Set<String>] = [
          "theme": ["system", "light", "dark"],
          "filter": ["All", "Photos", "Videos"],
          "sort": ["newest", "oldest"],
        ]
        guard let values = call.arguments as? [String: String],
              Set(values.keys) == Set(allowed.keys),
              values.allSatisfy({ allowed[$0.key]?.contains($0.value) == true }) else {
          result(FlutterError(code: "invalid_argument", message: nil, details: nil))
          return
        }
        defaults.set(values, forKey: "clipshare_settings")
        result(true)
      default: result(FlutterMethodNotImplemented)
      }
    }
    let channel = FlutterMethodChannel(
      name: "clipshare/shared_links",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    BackgroundDownloads.didChange = { channel.invokeMethod("changed", arguments: nil) }
    BackgroundDownloads.reconcile(protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable) { _ in }
    _ = NotificationCenter.default.addObserver(
      forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main
    ) { _ in
      BackgroundDownloads.reconcile(protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable) { _ in }
    }
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "reconcile":
        BackgroundDownloads.reconcile(protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable) { result($0) }
      case "folders", "createFolder", "deleteFolder", "renameFolder", "move", "delete", "info":
        do {
          switch call.method {
          case "folders": result(try SharedLinks.folders())
          case "createFolder", "deleteFolder", "delete":
            guard let value = call.arguments as? String else { throw URLError(.badURL) }
            if call.method == "createFolder" { result(try SharedLinks.createFolder(value)) }
            else if call.method == "deleteFolder" { result(try SharedLinks.renameFolder(value, to: nil)) }
            else { result(try BackgroundDownloads.delete(value)) }
          case "renameFolder":
            guard let args = call.arguments as? [String: String], let from = args["from"], let to = args["to"] else { throw URLError(.badURL) }
            result(try SharedLinks.renameFolder(from, to: to))
          case "move":
            guard let args = call.arguments as? [String: Any], let ids = args["ids"] as? [String], let folder = args["folder"] as? String else { throw URLError(.badURL) }
            result(try SharedLinks.move(ids, folder: folder))
          default:
            _ = try SharedLinks.entries()
            result([
              "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
              "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
              "os": "iOS \(UIDevice.current.systemVersion)",
              "storageBytes": try SharedLinks.storageBytes(),
              "recoveredEntries": try SharedLinks.recoveredEntries(),
            ])
          }
        } catch {
          result(FlutterError(code: "library_action_failed", message: nil, details: nil))
        }
      case "list":
        do {
          result(try SharedLinks.entries().map(\.channelValue))
        } catch {
          result(FlutterError(code: "shared_links_unavailable", message: nil, details: nil))
        }
      case "play":
        guard let id = call.arguments as? String,
              let self, self.playDownload(id)
        else {
          result(FlutterError(code: "video_unavailable", message: nil, details: nil))
          return
        }
        result(nil)
      case "thumbnail", "preview":
        guard let id = call.arguments as? String,
              let file = self?.savedFile(id) else {
          result(nil)
          return
        }
        if file.pathExtension == "mp4" {
          let generator = AVAssetImageGenerator(asset: AVURLAsset(url: file))
          generator.appliesPreferredTrackTransform = true
          generator.maximumSize = CGSize(width: 400, height: 400)
          generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: .zero)]) {
            [generator] _, image, _, _, _ in
            _ = generator
            DispatchQueue.main.async { Self.sendPreview(image, result: result) }
          }
        } else {
          let size = call.method == "preview" ? 1600 : 400
          DispatchQueue.global(qos: .userInitiated).async {
            let image = CGImageSourceCreateWithURL(file as CFURL, nil).flatMap {
              CGImageSourceCreateThumbnailAtIndex($0, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: size,
              ] as CFDictionary)
            }
            DispatchQueue.main.async { Self.sendPreview(image, result: result) }
          }
        }
      case "addResolved":
        guard let arguments = call.arguments as? [String: String],
              let source = arguments["source"].flatMap({ URL(string: $0) }),
              SharedLinks.canonicalSource(source) != nil,
              let media = arguments["media"].flatMap({ URL(string: $0) })
        else {
          result(FlutterError(code: "invalid_argument", message: nil, details: nil))
          return
        }
        do {
          result(try BackgroundDownloads.start(
            media, inApp: true, source: source, replacingID: arguments["replacing"],
            title: arguments["title"], slot: arguments["slot"].flatMap { Int($0) } ?? 0,
            position: arguments["position"],
            sourceAlias: arguments["sharedSource"].flatMap { URL(string: $0) },
            folder: arguments["folder"]
          ))
        } catch {
          result(FlutterError(code: BackgroundDownloads.failureCode(error), message: nil, details: nil))
        }
      case "add", "retry", "cancel":
        guard let argument = call.arguments as? String else {
          result(FlutterError(code: "invalid_argument", message: nil, details: nil))
          return
        }
        do {
          switch call.method {
          case "add":
            guard let url = URL(string: argument) else { throw URLError(.badURL) }
            result(try BackgroundDownloads.start(url, inApp: true))
          case "retry":
            let entry = try SharedLinks.entry(argument)
            guard let url = URL(string: entry.url) else { throw URLError(.badURL) }
            result(try BackgroundDownloads.start(url, inApp: true, replacingID: argument))
          default:
            result(try BackgroundDownloads.cancel(argument))
          }
        } catch {
          result(FlutterError(code: BackgroundDownloads.failureCode(error), message: nil, details: nil))
        }
      case "saveToPhotos", "exportToFiles", "export":
        guard let id = call.arguments as? String, let file = self?.savedFile(id) else {
          result(FlutterError(code: "video_unavailable", message: nil, details: nil))
          return
        }
        if call.method == "saveToPhotos" || call.method == "export" {
          self?.saveToPhotos(file, result: result)
        } else if let presenter = self?.presenter() {
          presenter.present(UIDocumentPickerViewController(forExporting: [file], asCopy: true), animated: true)
          result(true)
        } else {
          result(FlutterError(code: "export_unavailable", message: nil, details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  override func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    if !BackgroundDownloads.reconnect(identifier: identifier, completion: completionHandler) {
      super.application(
        application, handleEventsForBackgroundURLSession: identifier,
        completionHandler: completionHandler
      )
    }
  }

  private func playDownload(_ id: String) -> Bool {
    guard let file = savedFile(id), file.pathExtension == "mp4",
          let root = presenter() else { return false }

    let player = AVPlayer(url: file)
    let controller = AVPlayerViewController()
    controller.player = player
    root.present(controller, animated: true) { player.play() }
    return true
  }

  private static func sendPreview(_ image: CGImage?, result: FlutterResult) {
    let data = image.flatMap { UIImage(cgImage: $0).jpegData(compressionQuality: 0.85) }
    result(data.map { FlutterStandardTypedData(bytes: $0) })
  }

  private func savedFile(_ id: String) -> URL? {
    guard let entry = try? SharedLinks.entry(id), entry.state == .saved,
          let file = try? SharedLinks.file(id, suffix: entry.imageExtension ?? "mp4"),
          FileManager.default.fileExists(atPath: file.path)
    else { return nil }
    return file
  }

  private func presenter() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    let root = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
    return root?.presentedViewController == nil ? root : nil
  }

  private func saveToPhotos(_ file: URL, result: @escaping FlutterResult) {
    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
      guard status == .authorized || status == .limited else {
        DispatchQueue.main.async {
          result(FlutterError(code: "photos_denied", message: nil, details: nil))
        }
        return
      }
      var resource = file
      if file.pathExtension == "webp" {
        let png = FileManager.default.temporaryDirectory
          .appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        if let source = CGImageSourceCreateWithURL(file as CFURL, nil),
           let output = CGImageDestinationCreateWithURL(
            png as CFURL, UTType.png.identifier as CFString, 1, nil
           ) {
          CGImageDestinationAddImageFromSource(output, source, 0, nil)
          if CGImageDestinationFinalize(output) { resource = png }
        }
        if resource == file {
          try? FileManager.default.removeItem(at: png)
          DispatchQueue.main.async {
            result(FlutterError(code: "export_failed", message: nil, details: nil))
          }
          return
        }
      }
      PHPhotoLibrary.shared().performChanges { [resource] in
        let request = PHAssetCreationRequest.forAsset()
        request.addResource(with: file.pathExtension == "mp4" ? .video : .photo,
                            fileURL: resource, options: nil)
      } completionHandler: { [resource] saved, _ in
        if resource != file { try? FileManager.default.removeItem(at: resource) }
        DispatchQueue.main.async {
          if saved {
            result(true)
          } else {
            result(FlutterError(code: "export_failed", message: nil, details: nil))
          }
        }
      }
    }
  }
}
