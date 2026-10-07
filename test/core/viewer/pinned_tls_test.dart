import 'dart:convert';
import 'dart:io';

import 'package:agentmux_mobile/core/viewer/pinned_tls.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Stand-in DER bytes; the pin is over whatever bytes the peer presents.
  final der = utf8.encode('a certificate, in DER');
  final pin = sha256.convert(der).toString();

  group('certificateMatchesPin', () {
    test('the presented certificate matching the pin is accepted', () {
      expect(certificateMatchesPin(der, pin), isTrue);
    });

    test('the pin is accepted in upper case or with colons', () {
      final colons = [
        for (var i = 0; i < pin.length; i += 2)
          pin.substring(i, i + 2).toUpperCase(),
      ].join(':');
      expect(certificateMatchesPin(der, colons), isTrue);
    });

    test('any other certificate is refused', () {
      final other = utf8.encode('another certificate');
      expect(certificateMatchesPin(other, pin), isFalse);
      // One flipped bit.
      final flipped = [...der]..[0] ^= 1;
      expect(certificateMatchesPin(flipped, pin), isFalse);
    });

    test('a pin that is not a fingerprint refuses everything', () {
      expect(certificateMatchesPin(der, ''), isFalse);
      expect(certificateMatchesPin(der, pin.substring(1)), isFalse);
      expect(certificateMatchesPin(der, 'x' * 64), isFalse);
    });
  });

  test('normalizeFingerprint', () {
    expect(normalizeFingerprint(pin.toUpperCase()), pin);
    expect(normalizeFingerprint(null), isNull);
    expect(normalizeFingerprint('${pin}00'), isNull);
  });

  test('isPinRejection: a refused handshake or certificate', () {
    final req = RequestOptions(path: '/');
    expect(isPinRejection(const HandshakeException('x')), isTrue);
    expect(
      isPinRejection(DioException.badCertificate(requestOptions: req)),
      isTrue,
    );
    expect(
      isPinRejection(DioException(
        requestOptions: req,
        error: const HandshakeException('x'),
      )),
      isTrue,
    );
    expect(
      isPinRejection(DioException.connectionTimeout(
        requestOptions: req,
        timeout: const Duration(seconds: 5),
      )),
      isFalse,
    );
  });
}
