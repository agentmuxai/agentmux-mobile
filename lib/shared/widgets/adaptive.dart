import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Widest a list or settings page gets before it stops growing and centres:
/// on an iPad, an unfolded foldable or a landscape phone a full-width row has
/// its name at one edge and its badges a screen away (A4 and I8 in
/// `docs/specs/SPEC_FORM_FACTORS_AND_EDGES_2026_11_04.md`).
const listMaxWidth = 640.0;

/// The shortest side from which a screen counts as a tablet or an unfolded
/// foldable (Material's medium width class starts here).
const tabletShortestSide = 600.0;

/// The same for the feed, whose lines of prose need a little more.
const feedMaxWidth = 760.0;

/// [child] in a column no wider than [maxWidth], centred and as tall as the
/// space (or as tall as it is, where the height is unbounded, as in a Column). The structure is the same at every width, so a window that crosses
/// the limit (a rotation, a fold) doesn't remount the screen and lose its
/// state. The side space counts as the safe area it overlaps: the child's
/// `MediaQuery` padding is reduced by what the margin already clears, so a
/// notch inset isn't applied twice.
class ContentWidth extends StatelessWidget {
  const ContentWidth({
    super.key,
    this.maxWidth = listMaxWidth,
    required this.child,
  });

  final double maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Only a tablet or a foldable's inner screen: a landscape phone keeps
        // its full width and its notch insets.
        final wide = media.size.shortestSide >= tabletShortestSide;
        final width = wide ? math.min(maxWidth, constraints.maxWidth) : constraints.maxWidth;
        final margin = (constraints.maxWidth - width) / 2;
        EdgeInsets cleared(EdgeInsets p) => p.copyWith(
          left: math.max(0, p.left - margin),
          right: math.max(0, p.right - margin),
        );
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            height: constraints.hasBoundedHeight ? constraints.maxHeight : null,
            child: MediaQuery(
              data: media.copyWith(
                padding: cleared(media.padding),
                viewPadding: cleared(media.viewPadding),
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// How far the leading edge of the top bar has to move in for an iPadOS
/// window's controls (close, minimise, arrange), which are drawn over the
/// window's top-leading corner and, on every pushed screen, over the back
/// arrow (I9 in the report). The controls are there when the app runs as a
/// window rather than full screen: the window is smaller than the display.
/// Zero elsewhere.
double windowControlsInset(BuildContext context) {
  if (defaultTargetPlatform != TargetPlatform.iOS) return 0;
  final view = View.of(context);
  final display = view.display.size / view.display.devicePixelRatio;
  // An iPad: the iPhones have no window controls.
  if (display.shortestSide < 600) return 0;
  final window = MediaQuery.sizeOf(context);
  final windowed =
      window.width < display.width - 1 || window.height < display.height - 1;
  return windowed ? windowControlsWidth : 0;
}

/// About the width of the three window-control dots plus their margin.
const windowControlsWidth = 70.0;

/// An app bar [child] whose content clears the window controls. The bar's own
/// background still runs to the edge; only its leading edge moves in.
class AppBarInset extends StatelessWidget implements PreferredSizeWidget {
  const AppBarInset({super.key, required this.child});

  final PreferredSizeWidget child;

  @override
  Size get preferredSize => child.preferredSize;

  @override
  Widget build(BuildContext context) {
    final inset = windowControlsInset(context);
    final media = MediaQuery.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    EdgeInsets moved(EdgeInsets p) =>
        rtl
            ? p.copyWith(right: math.max(p.right, inset))
            : p.copyWith(left: math.max(p.left, inset));
    // The bar's own SafeArea reads these, so its leading edge starts clear.
    return MediaQuery(
      data: media.copyWith(
        padding: moved(media.padding),
        viewPadding: moved(media.viewPadding),
      ),
      child: child,
    );
  }
}
