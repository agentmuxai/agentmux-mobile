import 'dart:convert';

import 'package:flutter/painting.dart';

import 'feed_theme.dart';
import 'transcript.dart';

/// Every per-tool fact the feed's tool rows use, in one place, as the
/// desktop keeps them in `tool-meta/tool-descriptors.ts`
/// (`SPEC_FEED_RENDERS_LIKE_THE_DESKTOP_PANE_2026_10_13.md` §6).
enum ToolKind { bash, read, write, edit, grep, glob, agent, webSearch, webFetch, mcp, other }

ToolKind toolKind(String name) => switch (name) {
      'Bash' || 'bash' || 'BashOutput' || 'PowerShell' => ToolKind.bash,
      'Read' || 'read' || 'read_file' || 'NotebookRead' => ToolKind.read,
      'Write' || 'write' || 'write_file' => ToolKind.write,
      'Edit' || 'edit' || 'str_replace_editor' || 'MultiEdit' || 'multiedit' || 'NotebookEdit' =>
        ToolKind.edit,
      'Grep' || 'grep' => ToolKind.grep,
      'Glob' || 'glob' => ToolKind.glob,
      'Agent' || 'Task' => ToolKind.agent,
      'WebSearch' || 'web_search' => ToolKind.webSearch,
      'WebFetch' || 'web_fetch' => ToolKind.webFetch,
      _ when name.startsWith('mcp__') => ToolKind.mcp,
      _ => ToolKind.other,
    };

/// The row's status glyph (`tool-meta/tool-status.ts`).
String toolGlyph(ToolCallItem tool) => switch (tool.state) {
      ToolState.running when tool.name == 'AskUserQuestion' => '❓',
      ToolState.running => '⏳',
      ToolState.done => '✓',
      ToolState.failed => '✗',
      ToolState.denied => '⊘',
      ToolState.cancelled => '⏹',
    };

/// The 2 px bar on the row's left.
Color toolBarColor(ToolState state) => switch (state) {
      ToolState.running => FeedColors.warning,
      ToolState.done => FeedColors.success,
      ToolState.failed => FeedColors.error,
      ToolState.denied || ToolState.cancelled => FeedColors.secondary,
    };

String toolIcon(ToolKind kind) => switch (kind) {
      ToolKind.bash => '🔧',
      ToolKind.read => '📖',
      ToolKind.write => '📝',
      ToolKind.edit => '✏️',
      ToolKind.grep => '🔍',
      ToolKind.glob => '📁',
      ToolKind.agent => '🤖',
      ToolKind.webSearch || ToolKind.webFetch => '🌐',
      ToolKind.mcp || ToolKind.other => '🛠️',
    };

/// The tool name's colour (`$tool-name-colors` in `_document-nodes.scss`).
Color toolNameColor(ToolKind kind) => switch (kind) {
      ToolKind.bash => FeedColors.termGreen,
      ToolKind.read => FeedColors.accent,
      ToolKind.write || ToolKind.edit => FeedColors.warning,
      ToolKind.grep || ToolKind.glob => FeedColors.termCyan,
      ToolKind.agent => FeedColors.termMagenta,
      _ => FeedColors.secondary,
    };

/// "mcp__agentmux__WhoAmI" → "agentmux · WhoAmI".
String? mcpDisplayName(String name) {
  if (!name.startsWith('mcp__')) return null;
  final rest = name.substring(5);
  final sep = rest.indexOf('__');
  if (sep <= 0 || sep + 2 >= rest.length) return null;
  return '${rest.substring(0, sep)} · ${rest.substring(sep + 2)}';
}

/// The header's tool name; null leaves it out (a globe and a query can
/// only be a web tool).
String? toolLabel(ToolCallItem tool, String detail) {
  final kind = toolKind(tool.name);
  if ((kind == ToolKind.webSearch || kind == ToolKind.webFetch) && detail.isNotEmpty) {
    return null;
  }
  if (kind == ToolKind.mcp) return mcpDisplayName(tool.name) ?? tool.name;
  return tool.name;
}

String _str(Map input, String key) {
  final v = input[key];
  return v is String ? v : '';
}

/// ".../x/a.ts".
String shortPath(String p) {
  final parts = p.replaceAll(r'\', '/').split('/');
  return parts.length <= 2 ? p : '.../${parts.sublist(parts.length - 2).join('/')}';
}

/// The call's main argument for the header: path, command, query.
String toolDetail(ToolCallItem tool) {
  final p = tool.input;
  final path = _str(p, 'file_path').isNotEmpty
      ? _str(p, 'file_path')
      : (_str(p, 'notebook_path').isNotEmpty ? _str(p, 'notebook_path') : _str(p, 'path'));
  return switch (toolKind(tool.name)) {
    ToolKind.read || ToolKind.write || ToolKind.edit => path,
    ToolKind.bash => _str(p, 'command').isNotEmpty ? _str(p, 'command') : tool.summary,
    ToolKind.grep => _grepDetail(p),
    ToolKind.glob => _str(p, 'pattern'),
    ToolKind.agent => _str(p, 'description').isNotEmpty ? _str(p, 'description') : _str(p, 'prompt'),
    ToolKind.webSearch => _str(p, 'query'),
    ToolKind.webFetch => _hostPath(_str(p, 'url')),
    ToolKind.mcp || ToolKind.other => '',
  }
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Whether the detail is a file path, cut from the left so the name stays.
bool toolDetailIsPath(ToolCallItem tool) => switch (toolKind(tool.name)) {
      ToolKind.read || ToolKind.write || ToolKind.edit => true,
      _ => false,
    };

String _hostPath(String url) {
  final u = Uri.tryParse(url);
  if (u == null || u.host.isEmpty) return url;
  return u.host + (u.path == '/' ? '' : u.path);
}

/// A Grep call: its pattern first, then what changes what it searches.
String _grepDetail(Map p) {
  final pattern = _str(p, 'pattern');
  if (pattern.isEmpty) return '';
  final context = p['-C'] ?? p['context'];
  final flags = [
    if (p['-i'] == true) '-i',
    if (p['multiline'] == true) '-U',
    if (p['-n'] == false) '-N',
    if (context != null) '-C$context',
    if (p['-A'] != null) '-A${p['-A']}',
    if (p['-B'] != null) '-B${p['-B']}',
  ].join(' ');
  final mode = _str(p, 'output_mode');
  return [
    pattern,
    if (_str(p, 'path').isNotEmpty) 'in ${shortPath(_str(p, 'path'))}',
    if (_str(p, 'glob').isNotEmpty) _str(p, 'glob'),
    if (_str(p, 'type').isNotEmpty) 'type:${_str(p, 'type')}',
    if (flags.isNotEmpty) flags,
    if (mode.isNotEmpty && mode != 'files_with_matches') mode,
    if (p['head_limit'] != null) 'limit ${p['head_limit']}',
    if (p['offset'] != null) 'offset ${p['offset']}',
  ].join(' · ');
}

/// A Read's range, "120:179 of 456", when known.
String? readRange(ToolCallItem tool) {
  if (toolKind(tool.name) != ToolKind.read) return null;
  final f = tool.facts;
  final start = f.startLine;
  final n = f.numLines;
  if (start != null && n != null && n > 0) {
    final total = f.totalLines;
    final range = '$start:${start + n - 1}';
    return total == null ? range : '$range of $total';
  }
  final offset = tool.input['offset'];
  final limit = tool.input['limit'];
  if (offset is num && limit is num) return '${offset.toInt()}:${(offset + limit - 1).toInt()}';
  if (offset is num) return '${offset.toInt()}:';
  return null;
}

/// The header pill: a compact result summary.
class ToolPill {
  const ToolPill(this.label, this.color);
  final String label;
  final Color color;
}

String _plural(int n, String one, [String? many]) => '$n ${n == 1 ? one : (many ?? '${one}s')}';

ToolPill? toolPill(ToolCallItem tool) {
  if (tool.state != ToolState.done && tool.state != ToolState.failed) return null;
  final result = tool.result;
  switch (toolKind(tool.name)) {
    case ToolKind.bash:
      final exit = bashExit(tool.facts.stdout ?? result);
      if (exit == null) return null;
      return ToolPill(
        'exit ${exit.code}',
        exit.code == 0 ? FeedColors.successText : FeedColors.errorText,
      );
    case ToolKind.write:
      if (tool.state != ToolState.done) return null;
      final content = tool.input['content'];
      return ToolPill(
        content is String ? formatBytes(utf8.encode(content).length) : 'written',
        FeedColors.warningText,
      );
    case ToolKind.edit:
      if (tool.state != ToolState.done) return null;
      final f = tool.facts;
      final changed = (f.linesAdded ?? 0) + (f.linesRemoved ?? 0);
      return ToolPill(
        f.linesAdded == null ? 'edited' : _plural(changed, 'line'),
        FeedColors.warningText,
      );
    case ToolKind.grep:
      if (result == null || tool.state != ToolState.done) return null;
      final (n, noun) = grepCount(result, _str(tool.input, 'output_mode'));
      if (n == null) return null;
      return ToolPill(
        noun == 'file' ? _plural(n, 'file') : _plural(n, 'match', 'matches'),
        FeedColors.termCyan,
      );
    case ToolKind.glob:
      if (result == null || tool.state != ToolState.done) return null;
      final files = globFiles(result);
      return ToolPill(_plural(files.length, 'file'), FeedColors.termCyan);
    case ToolKind.webSearch:
      final n = webSearchLinks(result ?? '').length;
      return n == 0 ? null : ToolPill(_plural(n, 'source'), FeedColors.accent);
    default:
      return null;
  }
}

/// How many matches or files a Grep result lists.
(int?, String) grepCount(String result, String mode) {
  final first = result.split('\n').first;
  final found = RegExp(r'^Found (\d+) (file|match|line)').firstMatch(first);
  if (found != null) {
    final n = int.parse(found[1]!);
    return (n, found[2] == 'file' ? 'file' : 'match');
  }
  if (result.trim().isEmpty || result.startsWith('No ')) {
    return (0, mode == 'content' ? 'match' : 'file');
  }
  final lines = result.split('\n').where((l) => l.trim().isNotEmpty).length;
  return (lines, mode == 'content' || mode == 'count' ? 'match' : 'file');
}

/// A Glob result's paths.
List<String> globFiles(String result) => [
      for (final l in result.split('\n'))
        if (l.trim().isNotEmpty && !l.startsWith('No files found') && !l.startsWith('(Results are truncated'))
          l.trim(),
    ];

/// A WebSearch result's sources: Claude Code writes them as
/// `Links: [{"title":…,"url":…}, …]`.
List<({String title, String url})> webSearchLinks(String result) {
  final out = <({String title, String url})>[];
  for (final m in RegExp(r'Links: (\[.*?\])\s*$', multiLine: true).allMatches(result)) {
    try {
      final list = jsonDecode(m[1]!);
      if (list is! List) continue;
      for (final l in list) {
        if (l is Map && l['url'] is String) {
          final title = l['title'];
          out.add((title: title is String && title.isNotEmpty ? title : l['url'] as String, url: l['url'] as String));
        }
      }
    } on FormatException {
      continue;
    }
  }
  return out;
}

/// `812 B`, `4.2 KB`, `1.3 MB`.
String formatBytes(int n) {
  if (n < 1024) return '$n B';
  if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
  return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// The desktop's "(1.2s)".
String formatToolDuration(int ms) => '(${(ms / 1000).toStringAsFixed(1)}s)';

/// Opens by default once finished: a result that is the content
/// (`presentation: "content"`).
bool isContentFirst(ToolCallItem tool) =>
    toolKind(tool.name) == ToolKind.webSearch &&
    (tool.state == ToolState.done || tool.state == ToolState.failed);

/// The user dismissed it: no hold after it finishes.
bool isDismissed(ToolState s) => s == ToolState.denied || s == ToolState.cancelled;
