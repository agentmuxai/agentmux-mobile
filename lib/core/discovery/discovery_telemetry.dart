import 'network_environment.dart';

/// Outcome of one scan attempt by one discovery layer (mDNS or UDP
/// broadcast). Distinct from a free-text `AppLogger` line — this is
/// structured data `DebugLogScreen` reads directly for its summary header,
/// so "what happened on the last scan" doesn't require parsing log text.
class ScanSummary {
  const ScanSummary({
    required this.layer,
    required this.outcome,
    required this.detail,
    required this.at,
  });

  /// `"mdns"` or `"udp_broadcast"`.
  final String layer;

  /// `"results"` (found at least one instance), `"empty"` (completed
  /// cleanly, found nothing), or `"error"` (threw).
  final String outcome;

  /// One-line human-readable detail, e.g. `"3 PTR record(s) seen, 1
  /// resolved"` or `"probe sent, 0 response(s) received"`.
  final String detail;

  final DateTime at;
}

/// Last-known structured discovery telemetry — written by the scanners and
/// `DiscoveryNotifier`, read by `DebugLogScreen`'s summary header. Lives
/// alongside `AppLogger`, not inside it: `AppLogger` stays a free-text
/// event log; this is the small, purpose-built "what's the current picture"
/// snapshot the spec calls for, kept as its own concept rather than grown
/// into AppLogger's responsibility. See
/// docs/specs/DISCOVERY_DIAGNOSTICS_TELEMETRY.md.
///
/// Session-lifetime only, same as `AppLogger`'s ring buffer — no
/// persistence, no remote reporting (spec's Scope (out)).
class DiscoveryTelemetry {
  DiscoveryTelemetry._();

  static NetworkSnapshot? lastNetworkSnapshot;
  static ScanSummary? lastMdnsSummary;
  static ScanSummary? lastUdpSummary;

  static void reset() {
    lastNetworkSnapshot = null;
    lastMdnsSummary = null;
    lastUdpSummary = null;
  }
}
