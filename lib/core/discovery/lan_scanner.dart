import 'package:flutter/foundation.dart';

import 'models/lan_instance.dart';

/// The `_agentmux._tcp` fields a desktop advertises in its TXT record, after
/// validation (see `MdnsScanner.parseTxt`).
typedef TxtFields = ({
  String? authKey,
  String? version,
  String? hostname,
  String? instanceId,
  String? channel,
  String? os,
  String? installId,
});

/// One way of browsing the LAN for `_agentmux._tcp` services, run once per
/// discovery round: it yields what it finds until the caller cancels it.
/// Failures are logged inside and end the stream quietly; discovery has
/// other layers to fall back on.
abstract class LanScanner {
  Stream<LanInstance> scan({bool logSummary = true});
}

/// How this platform browses the LAN for desktops.
enum LanBrowseMethod {
  /// The `multicast_dns` package: raw UDP multicast on port 5353. Works on
  /// Android, but on a real iOS device (iOS 14 and later) it needs Apple's
  /// restricted `com.apple.developer.networking.multicast` entitlement.
  multicastDns,

  /// The platform's own Bonjour browser (NWBrowser and DNSServiceResolve on
  /// iOS), which needs no entitlement: only `NSBonjourServices` listing
  /// `_agentmux._tcp` and `NSLocalNetworkUsageDescription` in Info.plist.
  bonjour,
}

LanBrowseMethod lanBrowseMethodFor(TargetPlatform platform) =>
    platform == TargetPlatform.iOS
        ? LanBrowseMethod.bonjour
        : LanBrowseMethod.multicastDns;

/// Whether the UDP broadcast probe can run here. iOS refuses a broadcast
/// send without the same multicast entitlement, so it is not tried there.
bool udpProbeSupportedOn(TargetPlatform platform) =>
    platform != TargetPlatform.iOS;

/// The [LanInstance] for one resolved service: [srvTarget] and [port] from
/// its SRV record, [address] from resolving that host, the rest from its
/// TXT record. Shared by every [LanScanner] so they agree on every field.
LanInstance lanInstanceFromService({
  required TxtFields txt,
  required String authKey,
  required String srvTarget,
  required int port,
  required String address,
}) =>
    LanInstance(
      hostname: txt.hostname ?? srvTarget.split('.').first,
      version: txt.version ?? '?',
      address: address,
      port: port,
      authKey: authKey,
      instanceId: txt.instanceId,
      channel: txt.channel,
      // `channels_running` is not in TXT (it changes); the fleet feed has it.
      os: txt.os,
      installId: txt.installId,
    );
