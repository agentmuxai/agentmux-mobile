import 'dart:convert';

/// The feed screen's document: an agent's transcript frames turned into
/// what the screen shows (`SPEC_AGENT_STATUS_AND_LIVE_PANE_FEED_2026_10_07.md`
/// 6.2). Claude-shaped streams (Claude Code, and Qwen Code, which writes the
/// same frames) get prompts, text, tool calls and turn dividers; any other
/// provider is shown as the plain text of each frame. Kept in memory only.
sealed class TranscriptItem {
  TranscriptItem(this.key);

  /// Stable identity for the list, unique within one [Transcript].
  final int key;
}

/// Something the user (or another agent) sent.
class PromptItem extends TranscriptItem {
  PromptItem(super.key, this.text);
  final String text;
}

/// The assistant's text, Markdown source.
class AssistantTextItem extends TranscriptItem {
  AssistantTextItem(super.key, this.text);
  final String text;
}

enum ToolState { running, done, failed }

/// One tool call, as one line, with its result once it arrives.
class ToolCallItem extends TranscriptItem {
  ToolCallItem(super.key, {required this.id, required this.name, this.summary = ''});
  final String id;
  final String name;

  /// The input field that says most about the call (the command, the path).
  String summary;
  ToolState state = ToolState.running;

  /// The result's text, capped at [Transcript.maxResultChars].
  String? result;

  /// Set when the desktop cut the result frame (over 64 KB): its size.
  int? truncatedBytes;
}

/// The end of a turn.
class TurnDividerItem extends TranscriptItem {
  TurnDividerItem(super.key, {this.durationMs, this.error});
  final int? durationMs;

  /// The turn's error text, when it ended in one.
  final String? error;
}

/// A frame the desktop cut because it was too large, not attributable to a
/// tool call.
class TruncatedItem extends TranscriptItem {
  TruncatedItem(super.key, this.bytes);
  final int? bytes;
}

/// A frame of a provider this app does not parse yet.
class PlainTextItem extends TranscriptItem {
  PlainTextItem(super.key, this.text);
  final String text;
}

/// Whether frames of [provider] are parsed as Claude Code stream-json. An
/// unknown (empty) provider is tried as Claude, the common case.
bool isClaudeShaped(String provider) {
  final p = provider.toLowerCase();
  return p.isEmpty || p.startsWith('claude') || p.startsWith('qwen');
}

class Transcript {
  Transcript({required this.provider, this.maxItems = 3000});

  final String provider;

  /// Oldest items are dropped past this, so a feed left open for hours
  /// stays bounded.
  final int maxItems;

  static const maxResultChars = 64 * 1024;
  static const maxSummaryChars = 200;

  late final bool _claude = isClaudeShaped(provider);
  final List<TranscriptItem> _items = [];
  final Map<String, ToolCallItem> _tools = {};
  int _nextKey = 0;

  List<TranscriptItem> get items => List.unmodifiable(_items);
  int get length => _items.length;

  void addFrames(Iterable<String> frames) {
    for (final f in frames) {
      if (_claude) {
        _claudeFrame(f);
      } else {
        _plainFrame(f);
      }
    }
    if (_items.length > maxItems) {
      final drop = _items.length - maxItems;
      for (final item in _items.take(drop)) {
        if (item is ToolCallItem) _tools.remove(item.id);
      }
      _items.removeRange(0, drop);
    }
  }

  static Map<String, dynamic>? _json(String frame) {
    final t = frame.trim();
    if (!t.startsWith('{')) return null;
    try {
      final v = jsonDecode(t);
      return v is Map<String, dynamic> ? v : null;
    } on FormatException {
      return null;
    }
  }

  // ─── Claude-shaped ─────────────────────────────────────────────────────────

  void _claudeFrame(String frame) {
    final f = _json(frame);
    if (f == null) return;
    final type = f['type'];
    if (type == 'amx_truncated') {
      _truncated(f);
      return;
    }
    // A subagent's own steps belong to its Task call, not the main thread.
    final parent = f['parent_tool_use_id'];
    if (parent is String && parent.isNotEmpty) return;
    switch (type) {
      case 'assistant':
        if (f['partial'] == true) return;
        final message = f['message'];
        if (message is Map) _assistant(message['content']);
      case 'user':
        if (f['isMeta'] == true) return;
        final message = f['message'];
        if (message is Map) _user(message['content']);
      case 'user_message':
        // AgentMux's own normalised record of a sent message.
        final m = f['message'];
        if (m is String && m.trim().isNotEmpty) {
          _items.add(PromptItem(_nextKey++, m));
        }
      case 'result':
        final duration = f['duration_ms'];
        String? error;
        if (f['is_error'] == true) {
          final r = f['result'];
          error = r is String && r.isNotEmpty ? r : 'The turn ended with an error';
        }
        _items.add(TurnDividerItem(
          _nextKey++,
          durationMs: duration is num ? duration.toInt() : null,
          error: error,
        ));
    }
    // `system` (init), `stream_event` (deltas of what an `assistant` frame
    // then carries whole), rate limits and the rest show nothing.
  }

  void _assistant(Object? content) {
    if (content is String) {
      if (content.trim().isNotEmpty) {
        _items.add(AssistantTextItem(_nextKey++, content));
      }
      return;
    }
    if (content is! List) return;
    for (final block in content) {
      if (block is! Map) continue;
      switch (block['type']) {
        case 'text':
          final text = block['text'];
          if (text is String && text.trim().isNotEmpty) {
            _items.add(AssistantTextItem(_nextKey++, text));
          }
        case 'tool_use':
          final id = block['id'];
          final name = block['name'];
          if (id is! String || name is! String) continue;
          final summary = toolSummary(name, block['input']);
          final existing = _tools[id];
          if (existing != null) {
            existing.summary = summary;
            continue;
          }
          final item =
              ToolCallItem(_nextKey++, id: id, name: name, summary: summary);
          _tools[id] = item;
          _items.add(item);
        // `thinking` and `redacted_thinking` are not shown.
      }
    }
  }

  void _user(Object? content) {
    if (content is String) {
      if (content.trim().isNotEmpty) _items.add(PromptItem(_nextKey++, content));
      return;
    }
    if (content is! List) return;
    // Text-only arrays are Claude Code's meta lines ("[Request interrupted
    // by user]"); like the desktop pane, only tool results are taken.
    for (final block in content) {
      if (block is! Map || block['type'] != 'tool_result') continue;
      final tool = _tools[block['tool_use_id']];
      if (tool == null) continue;
      tool.state = block['is_error'] == true ? ToolState.failed : ToolState.done;
      tool.result = _cap(_resultText(block['content']));
    }
  }

  static final _toolUseId = RegExp(r'"tool_use_id"\s*:\s*"([^"]{1,128})"');

  /// A frame cut by the desktop: its head may still say which tool call it
  /// answers; otherwise it is shown on its own line.
  void _truncated(Map<String, dynamic> f) {
    final bytes = f['bytes'] is num ? (f['bytes'] as num).toInt() : null;
    final head = f['head'];
    if (_claude && head is String) {
      final id = _toolUseId.firstMatch(head)?.group(1);
      final tool = id == null ? null : _tools[id];
      if (tool != null) {
        tool.state = RegExp(r'"is_error"\s*:\s*true').hasMatch(head)
            ? ToolState.failed
            : ToolState.done;
        tool.truncatedBytes = bytes ?? 0;
        return;
      }
    }
    _items.add(TruncatedItem(_nextKey++, bytes));
  }

  static String _resultText(Object? content) {
    if (content == null) return '';
    if (content is String) return content;
    if (content is List) {
      final texts = [
        for (final b in content)
          if (b is Map && b['type'] == 'text' && b['text'] is String)
            b['text'] as String,
      ];
      if (texts.length == content.length) return texts.join('\n');
    }
    try {
      return const JsonEncoder.withIndent('  ').convert(content);
    } catch (_) {
      return content.toString();
    }
  }

  static String _cap(String s) => s.length <= maxResultChars
      ? s
      : '${s.substring(0, maxResultChars)}\n…';

  // ─── other providers ───────────────────────────────────────────────────────

  void _plainFrame(String frame) {
    final f = _json(frame);
    if (f == null) {
      final t = frame.trim();
      if (t.isNotEmpty) _items.add(PlainTextItem(_nextKey++, _cap(t)));
      return;
    }
    if (f['type'] == 'amx_truncated') {
      _truncated(f);
      return;
    }
    final text = bestText(f);
    if (text != null && text.trim().isNotEmpty) {
      _items.add(PlainTextItem(_nextKey++, _cap(text)));
    }
  }

  /// The most readable text in a frame of an unknown shape.
  static String? bestText(Map<String, dynamic> f) {
    for (final k in const ['text', 'content', 'message', 'result', 'delta', 'output']) {
      final v = f[k];
      if (v is String && v.trim().isNotEmpty) return v;
    }
    final message = f['message'] ?? f['item'];
    if (message is Map<String, dynamic>) {
      final inner = bestText(message);
      if (inner != null) return inner;
      final content = message['content'];
      if (content is List) {
        final texts = [
          for (final b in content)
            if (b is Map && b['text'] is String) b['text'] as String,
        ];
        if (texts.isNotEmpty) return texts.join('\n');
      }
    }
    return null;
  }
}

/// The one-line summary of a tool call: the input field that says most
/// about it (`Bash  git status`, `Edit  lib/app.dart`).
String toolSummary(String name, Object? input) {
  if (input is! Map) return '';
  String? pick(List<String> keys) {
    for (final k in keys) {
      final v = input[k];
      if (v is String && v.trim().isNotEmpty) return v;
    }
    return null;
  }

  final value = switch (name) {
    'Bash' || 'BashOutput' || 'PowerShell' => pick(['command', 'bash_id']),
    'Read' || 'Edit' || 'Write' || 'MultiEdit' => pick(['file_path', 'path']),
    'NotebookEdit' || 'NotebookRead' => pick(['notebook_path']),
    'Grep' || 'Glob' => pick(['pattern', 'path']),
    'WebFetch' => pick(['url']),
    'WebSearch' => pick(['query']),
    'Task' || 'Agent' => pick(['description', 'prompt']),
    'TodoWrite' => input['todos'] is List
        ? '${(input['todos'] as List).length} items'
        : null,
    _ => null,
  };
  final text = value ??
      pick(const [
        'command',
        'file_path',
        'path',
        'pattern',
        'url',
        'query',
        'description',
        'name',
        'prompt',
      ]) ??
      _firstString(input);
  if (text == null) return '';
  final line = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return line.length <= Transcript.maxSummaryChars
      ? line
      : '${line.substring(0, Transcript.maxSummaryChars)}…';
}

String? _firstString(Map input) {
  for (final v in input.values) {
    if (v is String && v.trim().isNotEmpty) return v;
  }
  return null;
}
