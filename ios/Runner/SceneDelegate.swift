import Flutter
import UIKit

// The app's one window scene (UIApplicationSceneManifest in Info.plist).
class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    // Some plugins still look for the window through the app delegate
    // (flutter_web_auth_2 4.1, for the sign-in sheet): give them this scene's.
    (UIApplication.shared.delegate as? FlutterAppDelegate)?.window = window
  }
}
