import 'dart:io';

import '../discovery/peer_fields.dart';
import 'pinned_tls.dart';

/// What a scanned QR code asks for.
sealed class ScannedCode {
  const ScannedCode();
}

/// The older `agentmux://connect?host=&port=&token=` code: connect to a
/// channel's LAN routes with the key it carries.
class ConnectCode extends ScannedCode {
  const ConnectCode({required this.host, required this.port, required this.token});
  final String host;
  final int port;
  final String token;
}

/// `agentmux://pair?v=1&host=&port=&fp=&code=&hostname=&channel=`
/// (`SPEC_AGENT_STATUS_AND_LIVE_PANE_FEED_2026_10_07.md` 13.2): pair this
/// device with a computer's viewer listener, pinned to [fingerprint].
class PairCode extends ScannedCode {
  const PairCode({
    required this.host,
    required this.port,
    required this.fingerprint,
    required this.code,
    this.hostname,
    this.channel,
  });
  final String host;
  final int port;

  /// Normalised: 64 lowercase hex characters.
  final String fingerprint;

  /// The one-time pairing code: 10 characters of base32, upper case.
  final String code;
  final String? hostname;
  final String? channel;
}

final _hostnamePattern = RegExp(r'^[A-Za-z0-9._-]{1,253}$');
final _pairingCodePattern = RegExp(r'^[A-Z2-7]{10}$');

/// Parses a scanned QR code; null when it is not one this app understands
/// or a required field is missing or malformed. Everything in it is checked
/// before use: a QR code is untrusted input until the pinned handshake.
ScannedCode? parseScannedCode(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null) return null;
  if (uri.scheme == 'agentmux' && uri.host == 'pair') return _parsePair(uri);
  return _parseConnect(uri);
}

PairCode? _parsePair(Uri uri) {
  final q = uri.queryParameters;
  if (q['v'] != '1') return null;
  final host = q['host'];
  if (host == null || !_validHost(host)) return null;
  final port = _port(q['port']);
  if (port == null) return null;
  final fingerprint = normalizeFingerprint(q['fp']);
  if (fingerprint == null) return null;
  final code = q['code']?.toUpperCase();
  if (code == null || !_pairingCodePattern.hasMatch(code)) return null;
  return PairCode(
    host: host,
    port: port,
    fingerprint: fingerprint,
    code: code,
    hostname: _label(q['hostname']),
    channel: _label(q['channel']),
  );
}

/// `agentmux://connect?host=<ip>&port=<port>&token=<key>`; any URI carrying
/// those three is accepted, as before.
ConnectCode? _parseConnect(Uri uri) {
  final host = uri.queryParameters['host'];
  final token = uri.queryParameters['token'];
  if (host == null || host.isEmpty) return null;
  if (token == null || token.isEmpty) return null;
  final port = _port(uri.queryParameters['port']);
  if (port == null) return null;
  return ConnectCode(host: host, port: port, token: token);
}

bool _validHost(String host) =>
    InternetAddress.tryParse(host) != null || _hostnamePattern.hasMatch(host);

int? _port(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final port = int.tryParse(raw);
  if (port == null || port < 1 || port > 65535) return null;
  return port;
}

/// An optional display label: dropped when empty, too long or not plain.
String? _label(String? value) {
  if (value == null || value.isEmpty || value.length > 128) return null;
  return hasControlChar(value) ? null : value;
}
