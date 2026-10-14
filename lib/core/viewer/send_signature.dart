import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// What a signed request to the computer is signed over
/// (`SPEC_SEND_FROM_THE_PHONE_2026_10_13.md` 5.2.1): five lines, UTF-8,
/// joined by `\n` with none at the end. [path] is the request path as sent
/// (percent-encoded, no query), [timestampMs] the `X-Amxv-Timestamp` header,
/// [body] the exact bytes sent.
Uint8List signedString({
  required String method,
  required String path,
  required int timestampMs,
  required List<int> body,
}) =>
    Uint8List.fromList(utf8.encode([
      'amxv-sig-v1',
      method,
      path,
      '$timestampMs',
      sha256.convert(body).toString(),
    ].join('\n')));
