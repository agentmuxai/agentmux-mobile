import 'dart:io';

/// A snapshot of this device's active (non-loopback) network interfaces,
/// captured once per discovery session — see docs/specs/DISCOVERY_DIAGNOSTICS_TELEMETRY.md.
///
/// This is the single piece of information that would have made this app's
/// own investigation of "why isn't anything showing up" immediate instead of
/// requiring a manual `adb shell ip addr` detour outside the app entirely.
class NetworkSnapshot {
  const NetworkSnapshot({required this.interfaces, required this.hint});

  /// e.g. `["wlan0=10.0.2.16", "eth0=10.0.2.15"]` — no CIDR suffix, just
  /// `interfaceName=address` (matches `captureNetworkSnapshot()`'s actual
  /// formatting below; reagent P2 on PR #17 caught an earlier version of
  /// this comment implying a `/24` suffix that was never actually
  /// produced). Empty if no non-loopback interface with an address was
  /// found.
  final List<String> interfaces;

  /// Plain-language explanation when [interfaces] matches a known pattern
  /// that discovery cannot work from (NAT sandbox, CGNAT, link-local-only,
  /// no network) — null when nothing matched, which does NOT mean discovery
  /// will succeed, only that this specific known-bad-pattern list didn't
  /// recognize anything wrong.
  final String? hint;

  String format() =>
      interfaces.isEmpty ? 'no active network interface' : interfaces.join(', ');
}

/// Captures the current network snapshot. Never throws — `NetworkInterface.list()`
/// failing (permissions, platform quirk) is itself diagnostic information, so
/// it's folded into the hint rather than propagated.
Future<NetworkSnapshot> captureNetworkSnapshot() async {
  try {
    final ifaces = await NetworkInterface.list(includeLoopback: false);
    final addresses = <InternetAddress>[];
    final formatted = <String>[];
    for (final iface in ifaces) {
      for (final addr in iface.addresses) {
        addresses.add(addr);
        formatted.add('${iface.name}=${addr.address}');
      }
    }
    return NetworkSnapshot(
      interfaces: formatted,
      hint: classifyNetworkHint(addresses),
    );
  } catch (e) {
    return NetworkSnapshot(
      interfaces: const [],
      hint: 'could not enumerate network interfaces: $e',
    );
  }
}

// Known subnets/environments that discovery structurally cannot reach a real
// LAN from — see the spec for how each was identified. Kept as an explicit,
// reviewable list rather than a general "does this look weird" heuristic.
const _knownUnfriendlyCidrs = <String, String>{
  // QEMU/SLIRP — the Android emulator's default virtual NAT networking.
  // Confirmed live 2026-08-18 on AgentMux_Pixel9 (eth0/wlan0 both here).
  '10.0.2.0/24': 'this is expected on the Android emulator\'s default '
      'networking, not a bug. LAN discovery can\'t reach a real network from '
      'here; use manual IP entry with your desktop\'s real LAN address, or '
      '(development only) scripts/run-emulator.sh.',
  // Carrier-grade NAT — common on mobile data, some hotel/campus WiFi.
  '100.64.0.0/10': 'this looks like carrier-grade NAT (CGNAT), common on '
      'mobile data — LAN discovery needs both devices on the same real '
      'local network.',
};

/// Returns a plain-language hint if [addresses] only contains IPv4 addresses
/// matching a known-unfriendly pattern (or no addresses at all), else null.
/// IPv6-only address lists are left unclassified (not enough live evidence
/// yet to build a reviewable pattern list for it — see spec's Scope (out)).
String? classifyNetworkHint(List<InternetAddress> addresses) {
  final ipv4 = addresses.where((a) => a.type == InternetAddressType.IPv4).toList();
  if (addresses.isEmpty) {
    return 'no active network interface — this device has no network '
        'connectivity at all.';
  }
  if (ipv4.isEmpty) {
    // IPv6-only is unusual enough to flag, but not confidently classifiable.
    return null;
  }
  for (final addr in ipv4) {
    for (final entry in _knownUnfriendlyCidrs.entries) {
      if (_inCidr(addr.address, entry.key)) return entry.value;
    }
  }
  if (ipv4.every((a) => _inCidr(a.address, '169.254.0.0/16'))) {
    return 'only a link-local address (169.254.x.x) — this usually means '
        'no real network connection (DHCP never succeeded).';
  }
  return null;
}

int? _ipv4ToInt(String ip) {
  final parts = ip.split('.');
  if (parts.length != 4) return null;
  var result = 0;
  for (final p in parts) {
    final octet = int.tryParse(p);
    if (octet == null || octet < 0 || octet > 255) return null;
    result = (result << 8) | octet;
  }
  return result;
}

/// True if [ip] falls within [cidr] (e.g. `"10.0.2.5"` in `"10.0.2.0/24"`).
/// Proper bitwise prefix match — not a string-prefix check — so this is
/// correct for non-byte-aligned prefixes like `/10` (100.64.0.0/10).
bool _inCidr(String ip, String cidr) {
  final parts = cidr.split('/');
  final base = _ipv4ToInt(parts[0]);
  final prefixLen = int.tryParse(parts[1]);
  final ipInt = _ipv4ToInt(ip);
  if (base == null || ipInt == null || prefixLen == null) return false;
  if (prefixLen == 0) return true;
  if (prefixLen >= 32) return ipInt == base;
  final mask = 0xFFFFFFFF << (32 - prefixLen);
  return (ipInt & mask) == (base & mask);
}
