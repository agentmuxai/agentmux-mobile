import Flutter
import Security
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let deviceKeys = DeviceKeys()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "com.agentmux.agentmux_mobile/device_key",
        binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { [weak self] call, result in
        self?.deviceKeys.handle(call, result)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

// The device key a paired computer checks a sent message with
// (SPEC_SEND_FROM_THE_PHONE 5.2.1): ECDSA on P-256, signing only, never
// exportable. In the Secure Enclave when the device has one; the Simulator has
// none, so there it is an ordinary keychain key. One key per pairing, named by
// the alias Dart gives it. No user authentication: Enter has to just send.
final class DeviceKeys {
  private func tag(_ alias: String) -> Data { Data(alias.utf8) }

  private func query(_ alias: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassKey,
      kSecAttrApplicationTag as String: tag(alias),
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
    ]
  }

  func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
      let alias = args["alias"] as? String, !alias.isEmpty
    else {
      result(FlutterError(code: "bad_args", message: "no alias", details: nil))
      return
    }
    switch call.method {
    case "create":
      create(alias, result)
    case "sign":
      guard let data = args["data"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "bad_args", message: "no data", details: nil))
        return
      }
      sign(alias, data.data, result)
    case "delete":
      SecItemDelete(query(alias) as CFDictionary)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func create(_ alias: String, _ result: FlutterResult) {
    SecItemDelete(query(alias) as CFDictionary)
    var key = makeKey(alias, secureEnclave: true)
    if key == nil { key = makeKey(alias, secureEnclave: false) }
    guard let privateKey = key,
      let publicKey = SecKeyCopyPublicKey(privateKey),
      let point = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?
    else {
      result(FlutterError(code: "key_store", message: "create", details: nil))
      return
    }
    // The 65-byte uncompressed point, 0x04 || X || Y.
    result(FlutterStandardTypedData(bytes: point))
  }

  private func makeKey(_ alias: String, secureEnclave: Bool) -> SecKey? {
    var attributes: [String: Any] = [
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrKeySizeInBits as String: 256,
    ]
    var privateAttributes: [String: Any] = [
      kSecAttrIsPermanent as String: true,
      kSecAttrApplicationTag as String: tag(alias),
    ]
    if secureEnclave {
      guard
        let access = SecAccessControlCreateWithFlags(
          nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .privateKeyUsage, nil)
      else { return nil }
      attributes[kSecAttrTokenID as String] = kSecAttrTokenIDSecureEnclave
      privateAttributes[kSecAttrAccessControl as String] = access
    } else {
      privateAttributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    }
    attributes[kSecPrivateKeyAttrs as String] = privateAttributes
    return SecKeyCreateRandomKey(attributes as CFDictionary, nil)
  }

  private func sign(_ alias: String, _ data: Data, _ result: FlutterResult) {
    var q = query(alias)
    q[kSecReturnRef as String] = true
    var item: CFTypeRef?
    guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
      let found = item
    else {
      result(FlutterError(code: "key_store", message: "no key", details: nil))
      return
    }
    let key = found as! SecKey
    guard
      let signature = SecKeyCreateSignature(
        key, .ecdsaSignatureMessageX962SHA256, data as CFData, nil) as Data?
    else {
      result(FlutterError(code: "key_store", message: "sign", details: nil))
      return
    }
    // A DER (ASN.1) signature, as the computer checks.
    result(FlutterStandardTypedData(bytes: signature))
  }
}
