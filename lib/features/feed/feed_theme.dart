import 'package:flutter/material.dart';

/// The desktop agent pane's default dark theme, for the feed
/// (`SPEC_FEED_RENDERS_LIKE_THE_DESKTOP_PANE_2026_10_13.md` §3). Values are
/// agentmux's `frontend/app/theme.scss` tokens; the names say which.
abstract final class FeedColors {
  /// `--main-text-color`.
  static const text = Color(0xFFF7F7F7);

  /// `--secondary-text-color`.
  static const secondary = Color.fromRGBO(195, 200, 194, 1);

  /// `--grey-text-color`.
  static const grey = Color(0xFF666666);

  /// `--block-bg-solid-color`: the prompt block's text.
  static const blockSolid = Color(0xFF000000);

  /// `--accent-color`.
  static const accent = Color.fromRGBO(65, 159, 224, 1);

  /// `--user-input-color`: the prompt block's left bar.
  static const userInput = Color(0xFFE07832);

  /// `--success-text-color`, `--warning-text-color`, `--error-text-color`.
  static const successText = Color(0xFF10B981);
  static const warningText = Color(0xFFD97706);
  static const errorText = Color(0xFFFF8080);

  /// `--success-color`, `--warning-color`, `--error-color`: tool bars.
  static const success = Color.fromRGBO(78, 154, 6, 1);
  static const warning = Color.fromRGBO(224, 185, 86, 1);
  static const error = Color.fromRGBO(229, 77, 46, 1);

  /// `--info-color`.
  static const info = Color.fromRGBO(155, 108, 224, 1);

  /// `--border-color`.
  static const border = Color.fromRGBO(255, 255, 255, 0.16);

  /// `--panel-bg-color`: code blocks, blockquotes.
  static const panel = Color.fromRGBO(31, 33, 31, 0.5);

  /// `--hover-bg-color`: table zebra rows.
  static const hover = Color.fromRGBO(255, 255, 255, 0.1);

  /// `--term-bright-blue`: links in Markdown.
  static const link = Color(0xFF32AFFF);

  /// `--term-bright-green`, `--term-bright-cyan`, `--term-bright-magenta`.
  static const termGreen = Color(0xFF58C142);
  static const termCyan = Color(0xFF34E2E2);
  static const termMagenta = Color(0xFFAD7FA8);

  /// `color-mix(in srgb, <c> <pct>%, transparent)`.
  static Color tint(Color c, double fraction) =>
      c.withValues(alpha: c.a * fraction);
}

/// The platform's monospace font (open question §11.4: the desktop bundles
/// Hack; the phone uses what the system has).
const feedMono = 'monospace';
const feedMonoFallback = ['Menlo', 'Courier New', 'Courier'];

/// Prose, 14 as the desktop's `--markdown-font-size`.
const feedProse = TextStyle(fontSize: 14, height: 1.5, color: FeedColors.text);

/// Code, tool lines and previews: 12 as `--markdown-fixed-font-size`.
const feedCode = TextStyle(
  fontFamily: feedMono,
  fontFamilyFallback: feedMonoFallback,
  fontSize: 12,
  height: 1.45,
  color: FeedColors.text,
);

/// The desktop's spacing steps (`--space-0-5` … `--space-5`).
abstract final class FeedSpace {
  static const s0_5 = 2.0;
  static const s1 = 4.0;
  static const s1_5 = 6.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 20.0;
}
