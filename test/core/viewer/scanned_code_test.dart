import 'package:agentmux_mobile/core/viewer/scanned_code.dart';
import 'package:flutter_test/flutter_test.dart';

import 'viewer_fakes.dart';

String _pair({
  String? v = '1',
  String? host = '198.51.100.20',
  String? port = '29800',
  String? fp = testFingerprint,
  String? code = 'ABCDEFGH23',
  String? hostname = 'host-a',
  String? channel = 'stable',
}) {
  final q = {
    if (v != null) 'v': v,
    if (host != null) 'host': host,
    if (port != null) 'port': port,
    if (fp != null) 'fp': fp,
    if (code != null) 'code': code,
    if (hostname != null) 'hostname': hostname,
    if (channel != null) 'channel': channel,
  };
  return Uri(scheme: 'agentmux', host: 'pair', queryParameters: q).toString();
}

void main() {
  group('agentmux://pair', () {
    test('a full pair URL parses', () {
      final code = parseScannedCode(_pair()) as PairCode;
      expect(code.host, '198.51.100.20');
      expect(code.port, 29800);
      expect(code.fingerprint, testFingerprint);
      expect(code.code, 'ABCDEFGH23');
      expect(code.hostname, 'host-a');
      expect(code.channel, 'stable');
    });

    test('hostname and channel are optional', () {
      final code =
          parseScannedCode(_pair(hostname: null, channel: null)) as PairCode;
      expect(code.hostname, isNull);
      expect(code.channel, isNull);
    });

    test('an upper-case or colon-separated fingerprint is normalised', () {
      final colons = [
        for (var i = 0; i < testFingerprint.length; i += 2)
          testFingerprint.substring(i, i + 2).toUpperCase(),
      ].join(':');
      final code = parseScannedCode(_pair(fp: colons)) as PairCode;
      expect(code.fingerprint, testFingerprint);
    });

    test('a lower-case code is accepted as upper case', () {
      final code = parseScannedCode(_pair(code: 'abcdefgh23')) as PairCode;
      expect(code.code, 'ABCDEFGH23');
    });

    for (final (name, url) in [
      ('missing v', _pair(v: null)),
      ('another version', _pair(v: '2')),
      ('missing host', _pair(host: null)),
      ('a host with a path', _pair(host: '198.51.100.20/x')),
      ('missing port', _pair(port: null)),
      ('port 0', _pair(port: '0')),
      ('port too large', _pair(port: '70000')),
      ('a port that is not a number', _pair(port: 'http')),
      ('missing fingerprint', _pair(fp: null)),
      ('a short fingerprint', _pair(fp: 'abcd')),
      ('a fingerprint that is not hex', _pair(fp: 'z' * 64)),
      ('missing code', _pair(code: null)),
      ('a code of the wrong length', _pair(code: 'ABC')),
      ('a code outside base32', _pair(code: 'ABCDEFGH01')),
    ]) {
      test('refused: $name', () {
        expect(parseScannedCode(url), isNull);
      });
    }

    test('a control character drops a display label, not the code', () {
      final code =
          parseScannedCode(_pair(hostname: 'host\u0001a')) as PairCode;
      expect(code.hostname, isNull);
    });
  });

  group('agentmux://connect (unchanged)', () {
    test('still parses', () {
      final code = parseScannedCode(
        'agentmux://connect?host=198.51.100.20&port=29702&token=k',
      ) as ConnectCode;
      expect(code.host, '198.51.100.20');
      expect(code.port, 29702);
      expect(code.token, 'k');
    });

    test('missing token is refused', () {
      expect(
        parseScannedCode('agentmux://connect?host=198.51.100.20&port=1'),
        isNull,
      );
    });

    test('junk is refused', () {
      expect(parseScannedCode('hello'), isNull);
      expect(parseScannedCode('https://example.com/'), isNull);
    });
  });
}
