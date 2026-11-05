import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_provider.dart';
import '../../shared/theme/app_theme.dart';
import 'fleet_status.dart';

const muxbusSignInLabel = 'MuxBus Sign in';

String muxbusSignedInLabel(String? email) =>
    email == null || email.isEmpty
        ? 'MuxBus: signed in'
        : 'MuxBus: signed in as $email';

/// The discovery screen's footer, always on screen below the host list.
/// Signed out it is one big "MuxBus Sign in" button that opens the MuxBus
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
    final inBand = band >= minBand && !keyboard;
    final aboveButton = band < minBand && !keyboard;

    final button = FilledButton.icon(
      key: const ValueKey('muxbus-account-bar'),
      onPressed: () => context.push(signedIn ? '/settings' : '/login'),
      style: FilledButton.styleFrom(
        minimumSize: Size.fromHeight(compact ? 44 : 56),
        padding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: compact ? 6 : 12,
        ),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
          if (aboveButton)
            FleetStatusLine(status: status, indicatorGap: false, height: 28),
          SafeArea(
            top: false,
            // The band below the button holds the status line and takes the
            // bottom inset itself.
            bottom: !inBand,
            minimum: EdgeInsets.fromLTRB(12, top, 12, bottom),
            child: button,
          ),
          if (inBand)
            FleetStatusLine(status: status, indicatorGap: true, height: band),
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

  static const _style = TextStyle(color: AppColors.textSecondary, fontSize: 11);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: status.spoken,
      child: ExcludeSemantics(
        child: MediaQuery.withNoTextScaling(
          child: SizedBox(
            height: height,
            // Clear of the curved corners and the notch or island side.
            child: SafeArea(
              top: false,
              bottom: false,
              minimum: const EdgeInsets.symmetric(horizontal: 22),
              child: LayoutBuilder(builder: _line),
            ),
          ),
        ),
      ),
    );
  }

  Widget _line(BuildContext context, BoxConstraints c) {
    final half = (c.maxWidth - (indicatorGap ? _indicator : 0)) / 2;
    final short = indicatorGap && half < 118;
    final left = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: status.live ? AppColors.success : AppColors.textMuted,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            status.left(short: short),
            style: _style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    final right = Text(
      status.right,
      style: _style,
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
