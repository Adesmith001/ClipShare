import AVKit
import Flutter
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
    if identifier.hasPrefix(BackgroundDownloads.sessionPrefix) {
      BackgroundDownloads.reconnect(identifier: identifier, completion: completionHandler)
    } else {
      super.application(
        application, handleEventsForBackgroundURLSession: identifier,
        completionHandler: completionHandler
      )
    }
  }

  private func playDownload(_ id: String) -> Bool {
    guard let entry = try? SharedLinks.entry(id), entry.state == .saved,
          let file = try? SharedLinks.file(id, suffix: "mp4"),
          FileManager.default.fileExists(atPath: file.path),
          let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
          let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController
    else { return false }

    let player = AVPlayer(url: file)
    let controller = AVPlayerViewController()
    controller.player = player
    root.present(controller, animated: true) { player.play() }
    return true
  }
}
