import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/viewer/paired_hosts_repository.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/adaptive.dart';
import '../discovery/qr_scan_screen.dart';

/// What AgentMux is, in one sentence. The welcome page and the screen with
/// no computers both say it.
const whatAgentMuxIs =
    'AgentMux runs AI coding agents on your computer. '
    'This app lets you watch and steer them from your phone.';

/// Where the pairing QR code is, as the scanner's own screen names it.
const whereTheQrCodeIs =
    'On your computer, open AgentMux and choose "Pair a device". '
    'Then scan the QR code it shows.';

const welcomePoints = <(IconData, String)>[
  (
    Icons.dynamic_feed_outlined,
    'See what each agent is doing: its live feed, its tasks and how busy '
        'the computer is.',
  ),
  (
    Icons.chat_bubble_outline,
    'Send an agent a message. It arrives in its conversation on your '
        'computer.',
  ),
  (
    Icons.wifi_tethering,
    'Find your computers on the same Wi-Fi, pair by QR code, or sign in to '
        'reach them from anywhere.',
  ),
];

const welcomeNextText =
    'Next, the app looks for AgentMux on your network. Your phone may ask '
    'you to allow that.';

/// Where "the welcome page was shown" is kept.
const welcomeSeenKey = 'welcome_seen_v1';

/// Whether the welcome page has been shown on this device. A store that can't
/// be read counts as shown: the welcome never stands between a person and
/// their computers.
class WelcomeSeen extends AsyncNotifier<bool> {
  @override
  FutureOr<bool> build() async {
    try {
      return await ref.read(secureStoreProvider).read(welcomeSeenKey) != null;
    } catch (_) {
      return true;
    }
  }

  /// The person has moved on from the welcome page. Saved best-effort.
  Future<void> markSeen() async {
    state = const AsyncData(true);
    try {
      await ref.read(secureStoreProvider).write(welcomeSeenKey, '1');
    } catch (_) {
      // Shown again at the next launch; nothing else depends on it.
    }
  }
}

final welcomeSeenProvider =
    AsyncNotifierProvider<WelcomeSeen, bool>(WelcomeSeen.new);

/// AgentMux's mark, as the app icon draws it.
class AppMark extends StatelessWidget {
  const AppMark({super.key, this.size = 64});
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Image.asset(
      'assets/icon/icon.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
    ),
  );
}

/// The first launch: what AgentMux is, and the two ways on. Shown once, and
/// before the app looks at the network, so the phone's "find devices on your
/// local network" question comes after the reason for it.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    Future<void> seen() => ref.read(welcomeSeenProvider.notifier).markSeen();

    return Scaffold(
      backgroundColor: palette.background,
      body: ContentWidth(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: AppMark()),
                    const SizedBox(height: 16),
                    // The title is chrome: it does not grow past twice its size.
                    MediaQuery.withClampedTextScaling(
                      maxScaleFactor: 2,
                      child: Text(
                        'AgentMux',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      whatAgentMuxIs,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 16,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 24),
                    for (final (icon, text) in welcomePoints)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(icon, size: 20, color: palette.primary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                text,
                                style: TextStyle(
                                  color: palette.textSecondary,
                                  fontSize: 14,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      key: const ValueKey('welcome-scan'),
                      icon: const Icon(Icons.qr_code_scanner, size: 20),
                      label: const Text('Scan QR code'),
                      // The scanner opens over this page first: once the
                      // welcome counts as seen, this page is gone.
                      onPressed: () {
                        unawaited(showQrScanScreen(context));
                        unawaited(seen());
                      },
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      key: const ValueKey('welcome-continue'),
                      onPressed: seen,
                      child: const Text('Continue'),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      welcomeNextText,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: palette.textMuted, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () => context.push('/demo'),
                      child: const Text('View a demo fleet'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
