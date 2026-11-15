import AVKit
import Flutter
import Photos
import UIKit

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
    let channel = FlutterMethodChannel(
      name: "clipshare/shared_links",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    BackgroundDownloads.didChange = { channel.invokeMethod("changed", arguments: nil) }
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
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
            result(try BackgroundDownloads.start(url, inApp: true, retryID: argument))
          default:
            result(try BackgroundDownloads.cancel(argument))
          }
        } catch {
          result(FlutterError(code: "download_action_failed", message: nil, details: nil))
        }
      case "saveToPhotos", "exportToFiles":
        guard let id = call.arguments as? String, let file = self?.savedVideo(id) else {
          result(FlutterError(code: "video_unavailable", message: nil, details: nil))
          return
        }
        if call.method == "saveToPhotos" {
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
    guard let file = savedVideo(id), let root = presenter() else { return false }

    let player = AVPlayer(url: file)
    let controller = AVPlayerViewController()
    controller.player = player
    root.present(controller, animated: true) { player.play() }
    return true
  }

  private func savedVideo(_ id: String) -> URL? {
    guard let entry = try? SharedLinks.entry(id), entry.state == .saved,
          let file = try? SharedLinks.file(id, suffix: "mp4"),
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
      PHPhotoLibrary.shared().performChanges {
        let request = PHAssetCreationRequest.forAsset()
        request.addResource(with: .video, fileURL: file, options: nil)
      } completionHandler: { saved, _ in
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
