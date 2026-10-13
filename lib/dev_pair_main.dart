// Dev only, never the release target: an emulator has no camera to scan the
// desktop's pairing QR with, so this entrypoint pairs with the
// `agentmux://pair?...` link given at build time through the app's own
// PairingService (the same call the QR screen makes), then starts the normal
// app. CLAUDE.md's "Pairing from the emulator" says how to get the link.
//
//   flutter run -t lib/dev_pair_main.dart --dart-define=AGENTMUX_DEV_PAIR_B64=<base64 of the link>
// (base64: on Windows `flutter` is a .bat, and cmd splits the link at its `&`s)
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/viewer/pairing_service.dart';
import 'core/viewer/scanned_code.dart';

const _pairB64 = String.fromEnvironment('AGENTMUX_DEV_PAIR_B64');
final _pairUrl = _pairB64.isEmpty ? '' : utf8.decode(base64Decode(_pairB64));

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer();
  final code = _pairUrl.isEmpty ? null : parseScannedCode(_pairUrl);
  if (code is PairCode) {
    try {
      final host = await container.read(pairingServiceProvider).pair(code);
      debugPrint('dev-pair: paired with ${host.hostname} at ${host.host}:${host.port}');
    } catch (e) {
      debugPrint('dev-pair: failed: $e');
    }
  } else if (_pairUrl.isNotEmpty) {
    debugPrint('dev-pair: not a pairing link');
  }
  runApp(UncontrolledProviderScope(container: container, child: const AgentMuxApp()));
}
