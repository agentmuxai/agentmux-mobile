import 'dart:io';

import 'package:flutter/services.dart';

/// Wraps the Android-only `WifiManager.MulticastLock`, without which mDNS
/// packets are silently dropped on API <=33 (see MainActivity.kt). No-op on
/// every other platform.
class AndroidMulticastLock {
  static const _channel =
      MethodChannel('com.agentmux.agentmux_mobile/multicast_lock');

  static Future<void> acquire() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('acquire');
    } on PlatformException {
      // Best-effort: discovery still works if this fails or isn't needed.
    }
  }

  static Future<void> release() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('release');
    } on PlatformException {
      // Best-effort.
    }
  }
}
