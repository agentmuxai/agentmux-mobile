import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// Certificate pinning for the desktop's viewer listener
/// (`SPEC_AGENT_STATUS_AND_LIVE_PANE_FEED_2026_10_07.md` sections 4.2 and
/// 13.2). The desktop's certificate is self-signed; the only thing that makes
/// it trusted is that its fingerprint matches the one in the pairing QR code,
/// which the user scanned off the computer's own screen. No CA is trusted, no
/// host name is checked, and there is no trust-on-first-use.

final _fingerprintPattern = RegExp(r'^[0-9a-f]{64}$');

/// The fingerprint in its canonical form (64 lowercase hex characters, the
/// SHA-256 of the certificate's DER bytes), or null when [value] is not one.
/// Upper case and `:` separators are accepted, since people copy them that
/// way; nothing else is.
String? normalizeFingerprint(String? value) {
  if (value == null) return null;
  final hex = value.replaceAll(':', '').toLowerCase();
  return _fingerprintPattern.hasMatch(hex) ? hex : null;
}

/// Lowercase hex SHA-256 of [der].
String certificateFingerprint(List<int> der) => sha256.convert(der).toString();

/// Whether the certificate whose DER bytes are [der] is the pinned one. This
/// is the whole of the TLS validation: a mismatch, or a pin that is not a
/// valid fingerprint, is refused.
bool certificateMatchesPin(List<int> der, String pin) {
  final expected = normalizeFingerprint(pin);
  if (expected == null) return false;
  final actual = certificateFingerprint(der);
  // Constant time over the fixed length, though the pin is not a secret.
  var diff = 0;
  for (var i = 0; i < expected.length; i++) {
    diff |= expected.codeUnitAt(i) ^ actual.codeUnitAt(i);
  }
  return diff == 0;
}

/// An [HttpClient] that trusts exactly one certificate, by fingerprint.
///
/// With no trusted roots every certificate fails the platform's own check,
/// so every handshake reaches [HttpClient.badCertificateCallback], which
/// accepts only the pinned one (its host name is not looked at: the desktop
/// is reached by address). A refused handshake fails before any request
/// bytes, such as a pairing code or a token, are sent.
HttpClient pinnedHttpClient(String pin) {
  final client = HttpClient(context: SecurityContext(withTrustedRoots: false))
    ..connectionTimeout = const Duration(seconds: 5);
  client.badCertificateCallback =
      (cert, host, port) => certificateMatchesPin(cert.der, pin);
  return client;
}

/// A Dio adapter over [pinnedHttpClient], which also re-checks the
/// certificate of every response.
HttpClientAdapter pinnedAdapter(String pin) => IOHttpClientAdapter(
      createHttpClient: () => pinnedHttpClient(pin),
      validateCertificate: (cert, host, port) =>
          cert != null && certificateMatchesPin(cert.der, pin),
    );

/// Whether [error] is the TLS pin refusing the desktop's certificate.
bool isPinRejection(Object error) {
  // A HandshakeException is a TlsException.
  if (error is TlsException) return true;
  if (error is DioException) {
    return error.type == DioExceptionType.badCertificate ||
        error.error is TlsException;
  }
  return false;
}
