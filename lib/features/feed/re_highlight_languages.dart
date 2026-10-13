import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/csharp.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/diff.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/ini.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/powershell.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/shell.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/swift.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart';

/// The languages the feed highlights
/// (`SPEC_FEED_RENDERS_LIKE_THE_DESKTOP_PANE_2026_10_13.md` §4.1). Only
/// these are imported, so the app doesn't carry every grammar.
final Map<String, Mode> feedLanguages = {
  'bash': langBash,
  'shell': langShell,
  'powershell': langPowershell,
  'json': langJson,
  'yaml': langYaml,
  'ini': langIni,
  'markdown': langMarkdown,
  'rust': langRust,
  'typescript': langTypescript,
  'javascript': langJavascript,
  'python': langPython,
  'go': langGo,
  'dart': langDart,
  'kotlin': langKotlin,
  'swift': langSwift,
  'c': langC,
  'cpp': langCpp,
  'csharp': langCsharp,
  'java': langJava,
  'xml': langXml,
  'css': langCss,
  'sql': langSql,
  'diff': langDiff,
};

/// Fence names and file extensions the grammars don't list themselves.
const languageAliases = {
  'zsh': 'bash',
  'sh': 'bash',
  'jsonc': 'json',
  'json5': 'json',
  'jsonl': 'json',
  'toml': 'ini',
  'cfg': 'ini',
  'conf': 'ini',
  'html': 'xml',
  'htm': 'xml',
  'svg': 'xml',
  'xaml': 'xml',
  'scss': 'css',
  'less': 'css',
  'h': 'c',
  'patch': 'diff',
  'golang': 'go',
  'psm1': 'powershell',
  'psd1': 'powershell',
};
