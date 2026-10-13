import 'dart:isolate';

import 'package:flutter/painting.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/github-dark-dimmed.dart';

import 're_highlight_languages.dart';

/// Syntax highlighting for code in the feed
/// (`SPEC_FEED_RENDERS_LIKE_THE_DESKTOP_PANE_2026_10_13.md` §4.1): the
/// highlight.js grammars and the `github-dark-dimmed` theme the desktop's
/// Markdown uses. Unknown languages, and text over [maxChars], stay plain.
abstract final class CodeHighlighter {
  /// Larger blocks are shown plain, as on the desktop.
  static const maxChars = 200 * 1024;

  /// Smaller blocks are highlighted on the spot; larger ones in an isolate.
  static const syncChars = 4 * 1024;

  static const _cacheSize = 64;
  static final _cache = <(String, String), TextSpan>{};

  static Highlight? _highlight;
  static Highlight get _engine =>
      _highlight ??= Highlight()..registerLanguages(feedLanguages);

  /// The registered language for a fence's info string or a file extension,
  /// or null.
  static String? language(String? name) {
    if (name == null) return null;
    final n = name.trim().toLowerCase();
    if (n.isEmpty) return null;
    final alias = languageAliases[n] ?? n;
    return _engine.getLanguage(alias) == null ? null : alias;
  }

  /// The language for a file path, by its extension.
  static String? languageForPath(String path) {
    final name = path.split(RegExp(r'[/\\]')).last.toLowerCase();
    if (name == 'dockerfile' || name == 'makefile') return null;
    final dot = name.lastIndexOf('.');
    if (dot < 0) return null;
    return language(name.substring(dot + 1));
  }

  /// [code] highlighted at once, or null when it isn't (unknown language,
  /// too large, or large enough for [highlightAsync]).
  static TextSpan? highlightSync(String code, String? language, TextStyle base) {
    if (language == null || code.length > syncChars) return null;
    return _cached(code, language) ?? _remember(code, language, _span(code, language, base));
  }

  /// [code] highlighted off the UI thread, or null when it can't be.
  static Future<TextSpan?> highlightAsync(
    String code,
    String? language,
    TextStyle base,
  ) async {
    if (language == null || code.length > maxChars) return null;
    final hit = _cached(code, language);
    if (hit != null) return hit;
    final span = await Isolate.run(() => _span(code, language, base));
    return _remember(code, language, span);
  }

  static TextSpan? cached(String code, String? language) =>
      language == null ? null : _cached(code, language);

  static TextSpan? _cached(String code, String language) {
    final key = (language, code);
    final hit = _cache.remove(key);
    if (hit != null) _cache[key] = hit;
    return hit;
  }

  static TextSpan? _remember(String code, String language, TextSpan? span) {
    if (span == null) return null;
    _cache[(language, code)] = span;
    while (_cache.length > _cacheSize) {
      _cache.remove(_cache.keys.first);
    }
    return span;
  }

  static TextSpan? _span(String code, String language, TextStyle base) {
    try {
      final result = _engine.highlight(code: code, language: language);
      final renderer = TextSpanRenderer(base, githubDarkDimmedTheme);
      result.render(renderer);
      return renderer.span;
    } catch (_) {
      // A grammar that fails on odd input: show the code plain.
      return null;
    }
  }
}
