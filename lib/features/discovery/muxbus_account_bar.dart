import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/adaptive.dart';
import 'fleet_status.dart';

const muxbusSignInLabel = 'MuxBus Sign in';

String muxbusSignedInLabel(String? email) =>
    email == null || email.isEmpty
        ? 'MuxBus: signed in'
        : 'MuxBus: signed in as $email';

/// The discovery screen's footer, always on screen below the host list.
/// Signed out it is one full-width "MuxBus Sign in" button that opens the MuxBus
/// sign-in page; signed in, the same button names the account and opens
/// Settings.
///
/// Under the button it says how the computers are reached, how many there
/// are and how many agents are working. On a phone with a home indicator
/// that line sits in the curved band at the bottom of the screen, which was
/// empty (design A in `docs/specs/SPEC_FORM_FACTORS_AND_EDGES_2026_11_04.md`):
/// the bar's colour runs to the corners, the text keeps clear of the curve
/// and of the indicator in the middle. Where there is no band (an iPhone SE,
/// Android three-button navigation) the same line is a row above the button
/// (design B), and while the keyboard is up it is left out.
class MuxbusAccountBar extends ConsumerWidget {
  const MuxbusAccountBar({super.key});

  /// The bottom inset at which the home-indicator band counts as a band:
  /// 34 pt in portrait on a Face ID iPhone, 20 in landscape, 25 on an iPad.
  static const minBand = 16.0;

  /// Above this the bottom inset is not a home-indicator band but a
  /// navigation bar (Android's three buttons report about 48 dp): the line
  /// goes above the button there, as with no band at all.
  static const maxBand = 40.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn =
        ref.watch(authProvider).valueOrNull == AuthStatus.authenticated;
    final email = signedIn ? ref.watch(accountEmailProvider).valueOrNull : null;
    final status = ref.watch(fleetStatusProvider);

    // On a short screen (a landscape phone; Material's compact height class is
    // under 480) the bar keeps its job but gives the list the room: it took
    // about a fifth of the height. An iPad or an unfolded foldable in landscape
    // is not short and keeps the full bar.
    final compact = MediaQuery.sizeOf(context).height < 480;
    final band = MediaQuery.viewPaddingOf(context).bottom;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final hasBand = band >= minBand && band < maxBand;
    final inBand = hasBand && !keyboard;
    final aboveButton = !hasBand && !keyboard;

    final button = FilledButton.icon(
      key: const ValueKey('muxbus-account-bar'),
      onPressed: () => context.push(signedIn ? '/settings' : '/login'),
      // The app's one button style: 44 high, square corners. Full width.
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(AppTheme.buttonHeight),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      icon: Icon(signedIn ? Icons.cloud_done_outlined : Icons.cloud_outlined),
      label: Text(
        signedIn ? muxbusSignedInLabel(email) : muxbusSignInLabel,
        maxLines: signedIn ? 1 : 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
      ),
    );

    final top = aboveButton ? 0.0 : (compact ? 4.0 : 8.0);
    final bottom = inBand ? 4.0 : (compact ? 4.0 : 12.0);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // On a tablet or an unfolded foldable the bar's content stays a
          // phone-wide column in the middle; only its colour runs edge to edge.
          if (aboveButton)
            ContentWidth(
              child: FleetStatusLine(
                status: status,
                indicatorGap: false,
                height: 28,
              ),
            ),
          ContentWidth(
            child: SafeArea(
              top: false,
              // The band below the button holds the status line and takes the
              // bottom inset itself.
              bottom: !inBand,
              minimum: EdgeInsets.fromLTRB(12, top, 12, bottom),
              // The button is chrome, not content: at the largest accessibility
              // sizes it was a quarter of the screen.
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: largeTextScale,
                child: button,
              ),
            ),
          ),
          if (inBand)
            ContentWidth(
              child: FleetStatusLine(
                status: status,
                indicatorGap: true,
                height: band,
              ),
            ),
        ],
      ),
    );
  }
}

/// The one-line fleet status: connection and computers at the leading edge,
/// working agents at the trailing edge. Not interactive (the bottom edge is
/// the system's swipe-home zone), muted, and never larger than its [height]:
/// its text does not follow the text size. With [indicatorGap] the middle is
/// left clear for the home indicator.
class FleetStatusLine extends StatelessWidget {
  const FleetStatusLine({
    super.key,
    required this.status,
    required this.indicatorGap,
    required this.height,
  });

  final FleetStatus status;
  final bool indicatorGap;
  final double height;

  /// The home indicator is about 134 pt wide; leave a little more.
  static const _indicator = 150.0;

  static TextStyle _style(BuildContext context) =>
      TextStyle(color: context.palette.textSecondary, fontSize: 11);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: status.spoken,
      child: ExcludeSemantics(
        child: MediaQuery.withNoTextScaling(
          child: SizedBox(
            height: height,
            // Clear of the curved corners and the notch or island side. A
            // phone's bottom corners are about 55 pt: 22 pt cut the last
            // letter of the trailing text.
            child: SafeArea(
              top: false,
              bottom: false,
              minimum: EdgeInsets.symmetric(
                horizontal: MediaQuery.sizeOf(context).shortestSide >= 360 ? 30 : 22,
              ),
              child: LayoutBuilder(builder: _line),
            ),
          ),
        ),
      ),
    );
  }

  Widget _line(BuildContext context, BoxConstraints c) {
    final half = (c.maxWidth - (indicatorGap ? _indicator : 0)) / 2;
    // Both halves are narrow beside the indicator (about 90 pt each on a
    // 393 pt phone): each has a short form instead of an ellipsis. (The
    // limits include the 30 pt kept clear of each rounded corner.)
    final short = indicatorGap && half < 110;
    // "● No computers" needs about 82 dp: a 320 dp phone's half is 55.
    final tiny = indicatorGap && half < 82;
    final shortRight = indicatorGap && half < 127;
    final left = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: status.live ? context.palette.success : context.palette.textMuted,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            status.left(short: short, tiny: tiny),
            style: _style(context),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    final right = Text(
      status.right(short: shortRight),
      style: _style(context),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    return Row(
      children: [
        Expanded(child: Align(alignment: Alignment.centerLeft, child: left)),
        if (indicatorGap) const SizedBox(width: _indicator),
        Expanded(child: Align(alignment: Alignment.centerRight, child: right)),
      ],
    );
  }
}
