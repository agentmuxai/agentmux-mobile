import 'package:flutter_test/flutter_test.dart';
import 'package:agentmux_mobile/core/discovery/mdns_scanner.dart';

void main() {
  group('MdnsScanner.parseTxt', () {
    test('reads os and install_id next to the existing fields', () {
      final txt = MdnsScanner.parseTxt([
        'auth_key=lan-a',
        'version=0.59.11',
        'hostname=narko',
        'channel=local-main',
        'os=windows',
        'install_id=testinstallidtestinstallid',
      ].join('\n'));
      expect(txt.authKey, 'lan-a');
      expect(txt.hostname, 'narko');
      expect(txt.channel, 'local-main');
      expect(txt.os, 'windows');
      expect(txt.installId, 'testinstallidtestinstallid');
    });

    test('an older desktop without them parses with nulls', () {
      final txt = MdnsScanner.parseTxt('auth_key=k\nversion=0.58.0');
      expect(txt.authKey, 'k');
      expect(txt.os, isNull);
      expect(txt.installId, isNull);
    });

    test('a malformed os or install_id is dropped', () {
      final txt =
          MdnsScanner.parseTxt('auth_key=k\nos=Mac OS X\ninstall_id=a b c');
      expect(txt.os, isNull);
      expect(txt.installId, isNull);
      expect(txt.authKey, 'k');
    });

    test('empty and junk text never throws', () {
      expect(MdnsScanner.parseTxt('').authKey, isNull);
      expect(MdnsScanner.parseTxt('noequals\n=\n==').authKey, isNull);
    });
  });
}
