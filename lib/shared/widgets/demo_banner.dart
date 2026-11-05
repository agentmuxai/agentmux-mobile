import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'adaptive.dart';

/// Persistent "you're looking at sample data" banner for demo-mode screens.
/// Deliberately loud (not just a small badge) — the whole point is that
/// nobody, reviewer or user, mistakes demo agents for a real connection.
///
/// Put it at the top of the body, not in `AppBar.bottom`: the app bar insets
/// its bottom widget by the side safe areas, which in landscape leaves dark
/// gaps beside the yellow. Here the colour runs to both edges and only the
/// text keeps clear of the notch or the Dynamic Island. It sizes itself from
/// the text, so a large text size wraps instead of overflowing.
class DemoBanner extends StatelessWidget {
  const DemoBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final colour = context.palette.warning;
    // Black on the dark mode's yellow, white on the light mode's brown.
    final ink =
        ThemeData.estimateBrightnessForColor(colour) == Brightness.dark
            ? Colors.white
            : Colors.black;
    return Container(
      width: double.infinity,
      color: colour,
      child: SafeArea(
        top: false,
        bottom: false,
        minimum: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        // A banner is chrome: it wraps at large text but stops growing at
        // the point where it would be a quarter of a small screen.
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: largeTextScale,
          child: Text(
            'DEMO DATA — not a live connection',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: ink,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
