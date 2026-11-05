import 'package:flutter/material.dart';

/// The colours of the feed (`SPEC_FEED_RENDERS_LIKE_THE_DESKTOP_PANE_2026_10_13.md`
/// §3), in a dark and a light set; screens read them with `context.feed` so
/// the feed follows the OS colour mode like the rest of the app. The dark set
/// is the desktop agent pane's default theme: values are agentmux's
/// `frontend/app/theme.scss` tokens, and the names say which. The light set
/// keeps the roles with darker shades that stay readable on white.
@immutable
class FeedPalette extends ThemeExtension<FeedPalette> {
  const FeedPalette({
    required this.brightness,
    required this.text,
    required this.secondary,
    required this.grey,
    required this.blockSolid,
    required this.accent,
    required this.userInput,
    required this.successText,
    required this.warningText,
    required this.errorText,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.border,
    required this.panel,
    required this.hover,
    required this.link,
    required this.termGreen,
    required this.termCyan,
    required this.termMagenta,
  });

  /// Which mode this set is for (it picks the syntax-highlighting theme).
  final Brightness brightness;

  /// `--main-text-color`.
  final Color text;

  /// `--secondary-text-color`.
  final Color secondary;

  /// `--grey-text-color`.
  final Color grey;

  /// `--block-bg-solid-color`: the prompt block's text.
  final Color blockSolid;

  /// `--accent-color`.
  final Color accent;

  /// `--user-input-color`: the prompt block's left bar.
  final Color userInput;

  /// `--success-text-color`, `--warning-text-color`, `--error-text-color`.
  final Color successText;
  final Color warningText;
  final Color errorText;

  /// `--success-color`, `--warning-color`, `--error-color`: tool bars.
  final Color success;
  final Color warning;
  final Color error;

  /// `--info-color`.
  final Color info;

  /// `--border-color`.
  final Color border;

  /// `--panel-bg-color`: code blocks, blockquotes.
  final Color panel;

  /// `--hover-bg-color`: table zebra rows.
  final Color hover;

  /// `--term-bright-blue`: links in Markdown.
  final Color link;

  /// `--term-bright-green`, `--term-bright-cyan`, `--term-bright-magenta`.
  final Color termGreen;
  final Color termCyan;
  final Color termMagenta;

  static const dark = FeedPalette(
    brightness: Brightness.dark,
    text: Color(0xFFF7F7F7),
    secondary: Color.fromRGBO(195, 200, 194, 1),
    grey: Color(0xFF666666),
    blockSolid: Color(0xFF000000),
    accent: Color.fromRGBO(65, 159, 224, 1),
    userInput: Color(0xFFE07832),
    successText: Color(0xFF10B981),
    warningText: Color(0xFFD97706),
    errorText: Color(0xFFFF8080),
    success: Color.fromRGBO(78, 154, 6, 1),
    warning: Color.fromRGBO(224, 185, 86, 1),
    error: Color.fromRGBO(229, 77, 46, 1),
    info: Color.fromRGBO(155, 108, 224, 1),
    border: Color.fromRGBO(255, 255, 255, 0.16),
    panel: Color.fromRGBO(31, 33, 31, 0.5),
    hover: Color.fromRGBO(255, 255, 255, 0.1),
    link: Color(0xFF32AFFF),
    termGreen: Color(0xFF58C142),
    termCyan: Color(0xFF34E2E2),
    termMagenta: Color(0xFFAD7FA8),
  );

  /// Dark text on white, the prompt block inverted (a dark box with light
  /// text), status text in the darker shades.
  static const light = FeedPalette(
    brightness: Brightness.light,
    text: Color(0xFF1F2328),
    secondary: Color(0xFF57606A),
    grey: Color(0xFF6E7781),
    blockSolid: Color(0xFFFFFFFF),
    accent: Color(0xFF0969DA),
    userInput: Color(0xFFC2571A),
    successText: Color(0xFF047857),
    warningText: Color(0xFF8F5B00),
    errorText: Color(0xFFB42318),
    success: Color.fromRGBO(56, 124, 4, 1),
    // Also text (a tool's name and glyph), so as dark as warningText.
    warning: Color.fromRGBO(143, 91, 0, 1),
    error: Color.fromRGBO(207, 58, 28, 1),
    info: Color(0xFF7C3AED),
    border: Color.fromRGBO(0, 0, 0, 0.14),
    panel: Color.fromRGBO(0, 0, 0, 0.05),
    hover: Color.fromRGBO(0, 0, 0, 0.06),
    link: Color(0xFF0969DA),
    termGreen: Color(0xFF1A7F37),
    termCyan: Color(0xFF0E7C86),
    termMagenta: Color(0xFF8250DF),
  );

  /// The palette of the theme in effect; the dark set where there is none (a
  /// bare MaterialApp in a test).
  static FeedPalette of(BuildContext context) =>
      Theme.of(context).extension<FeedPalette>() ?? dark;

  // The two sets are whole palettes: a change of mode switches between them
  // rather than blending 20 colours.
  @override
  FeedPalette copyWith() => this;

  @override
  FeedPalette lerp(ThemeExtension<FeedPalette>? other, double t) =>
      other is FeedPalette && t >= 0.5 ? other : this;
}

extension FeedPaletteContext on BuildContext {
  /// The feed's colours for the current (OS-chosen) colour mode.
  FeedPalette get feed => FeedPalette.of(this);

  /// Prose, 14 as the desktop's `--markdown-font-size`.
  TextStyle get feedProse => feedProseStyle(feed);

  /// Code, tool lines and previews: 12 as `--markdown-fixed-font-size`.
  TextStyle get feedCode => feedCodeStyle(feed);
}

/// [FeedPaletteContext.feedProse] for code that has the palette but no context.
TextStyle feedProseStyle(FeedPalette f) =>
    TextStyle(fontSize: 14, height: 1.5, color: f.text);

/// [FeedPaletteContext.feedCode] for code that has the palette but no context.
TextStyle feedCodeStyle(FeedPalette f) => TextStyle(
  fontFamily: feedMono,
  fontFamilyFallback: feedMonoFallback,
  fontSize: 12,
  height: 1.45,
  color: f.text,
);

/// `color-mix(in srgb, <c> <pct>%, transparent)`.
Color feedTint(Color c, double fraction) =>
    c.withValues(alpha: c.a * fraction);

/// The platform's monospace font (open question §11.4: the desktop bundles
/// Hack; the phone uses what the system has).
const feedMono = 'monospace';
const feedMonoFallback = ['Menlo', 'Courier New', 'Courier'];

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
