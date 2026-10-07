import 'pinned_tls.dart';

/// A discovered channel's pairing, and where its viewer listener is now:
/// discovery's address and `viewer_port` when it has them, else what was
/// stored.
class PairingMatch {
  const PairingMatch({
    required this.paired,
    required this.host,
    required this.port,
  });
  final PairedHost paired;
  final String host;
  final int port;

  /// Discovery found the listener somewhere other than the stored record.
  bool get moved => host != paired.host || port != paired.port;
}

/// One computer this device paired with: a viewer grant for one channel of
/// one AgentMux install (`SPEC_AGENT_STATUS_AND_LIVE_PANE_FEED_2026_10_07.md`
/// 13.2 and 13.4). Kept in secure storage only; [token] is a bearer secret
/// and is never logged.
class PairedHost {
  const PairedHost({
    required this.id,
    required this.token,
    required this.fingerprint,
    required this.host,
    required this.port,
    required this.hostname,
    required this.deviceId,
    required this.pairedAt,
    this.channel,
    this.installId,
    this.invalid = false,
  });

  /// Local identity of this record (routes and UI state key on it).
  final String id;

  /// `amxv_...`, sent as `Authorization: Bearer` inside the pinned session.
  final String token;

  /// The pinned certificate's SHA-256, lowercase hex.
  final String fingerprint;

  /// Where the viewer listener was last known to be. Discovery may report a
  /// newer address or port; see `matchPairing`.
  final String host;
  final int port;

  final String hostname;
  final String? channel;

  /// The install's WAN instance id, when the desktop reported one; the
  /// preferred way to recognise the install in discovery.
  final String? installId;

  /// The desktop's id for this device (what Revoke on the computer removes).
  final String deviceId;
  final DateTime pairedAt;

  /// The desktop refused the token (it was revoked there): the device must
  /// pair again before it can watch anything.
  final bool invalid;

  PairedHost copyWith({String? host, int? port, bool? invalid}) => PairedHost(
        id: id,
        token: token,
        fingerprint: fingerprint,
        host: host ?? this.host,
        port: port ?? this.port,
        hostname: hostname,
        channel: channel,
        installId: installId,
        deviceId: deviceId,
        pairedAt: pairedAt,
        invalid: invalid ?? this.invalid,
      );

  /// Whether [other] is a pairing with the same channel of the same install,
  /// so a new pairing replaces it.
  bool sameTarget(PairedHost other) {
    final a = installId;
    final b = other.installId;
    if (a != null && b != null) return a == b;
    return hostname.toLowerCase() == other.hostname.toLowerCase() &&
        channel == other.channel;
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'token': token,
        'fp': fingerprint,
        'host': host,
        'port': port,
        'hostname': hostname,
        'channel': channel,
        'install_id': installId,
        'device_id': deviceId,
        'paired_at': pairedAt.millisecondsSinceEpoch,
        'invalid': invalid,
      };

  /// Null for a record that is not well formed (it is then dropped, which
  /// only means pairing again).
  static PairedHost? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final token = json['token'];
    final fp = normalizeFingerprint(json['fp'] as String?);
    final host = json['host'];
    final port = json['port'];
    final hostname = json['hostname'];
    final deviceId = json['device_id'];
    final pairedAt = json['paired_at'];
    final channel = json['channel'];
    final installId = json['install_id'];
    if (id is! String ||
        token is! String ||
        fp == null ||
        host is! String ||
        port is! int ||
        hostname is! String ||
        deviceId is! String ||
        pairedAt is! int) {
      return null;
    }
    return PairedHost(
      id: id,
      token: token,
      fingerprint: fp,
      host: host,
      port: port,
      hostname: hostname,
      channel: channel is String ? channel : null,
      installId: installId is String ? installId : null,
      deviceId: deviceId,
      pairedAt: DateTime.fromMillisecondsSinceEpoch(pairedAt),
      invalid: json['invalid'] == true,
    );
  }
}
