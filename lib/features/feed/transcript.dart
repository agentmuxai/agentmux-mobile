import 'dart:convert';

/// The feed screen's document: an agent's transcript frames turned into
/// what the screen shows (`SPEC_AGENT_STATUS_AND_LIVE_PANE_FEED_2026_10_07.md`
/// 6.2). Claude-shaped streams (Claude Code, and Qwen Code, which writes the
/// same frames) get prompts, text and thinking (growing as they stream), tool
/// calls and turn dividers; any other
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

enum ToolState {
  running,
  done,
  failed,

  /// The user refused it.
  denied,

  /// Still running when the turn ended or was interrupted.
  cancelled,
}

/// The assistant's text while it streams, built from `stream_event` deltas.
/// Replaced by an [AssistantTextItem] once the whole message arrives.
class StreamingTextItem extends TranscriptItem {
  StreamingTextItem(super.key, [this.text = '']);
  String text;
}

/// What the model thought, shown as the desktop shows it: the full text,
/// muted. Grows from `thinking_delta`s while it streams; the whole block
/// replaces it once its message arrives.
class ThinkingItem extends TranscriptItem {
  ThinkingItem(super.key, [this.text = '']);
  String text;

  /// Still growing from `stream_event` deltas.
  bool get streaming => _streaming;
  bool _streaming = false;
}

/// One tool call: a header line, and a preview of its input or result.
class ToolCallItem extends TranscriptItem {
  ToolCallItem(
    super.key, {
    required this.id,
    required this.name,
    this.summary = '',
    Map<String, dynamic>? input,
  }) : input = input ?? const {};
  final String id;
  final String name;

  /// The input field that says most about the call (the command, the path).
  String summary;

  /// The call's input, as the model sent it.
  Map<String, dynamic> input;
  ToolState state = ToolState.running;

  /// The result's text, capped at [Transcript.maxResultChars].
  String? result;

  /// Set when the desktop cut the result frame (over 64 KB): its size.
  int? truncatedBytes;

  /// Set when the desktop cut the call's own frame (a large Write or Edit):
  /// its size. The input is then unknown.
  int? inputTruncatedBytes;

  /// What Claude Code's structured `tool_use_result` adds to the text.
  ToolFacts facts = const ToolFacts();

  /// How long the call took, when known.
  int? durationMs;

  /// When this device received the call, for a live call's duration.
  DateTime? receivedAt;
}

/// The parts of Claude Code's structured `tool_use_result` the previews and
/// header use. Only these are kept, never a file's text or the old file.
class ToolFacts {
  const ToolFacts({
    this.stdout,
    this.stderr,
    this.interrupted = false,
    this.startLine,
    this.numLines,
    this.totalLines,
    this.linesAdded,
    this.linesRemoved,
    this.created = false,
    this.unchanged = false,
    this.durationMs,
  });

  /// Bash's own streams.
  final String? stdout;
  final String? stderr;
  final bool interrupted;

  /// Where a Read's text sits in the file.
  final int? startLine;
  final int? numLines;
  final int? totalLines;

  /// An Edit's or Write's changed lines, from its patch.
  final int? linesAdded;
  final int? linesRemoved;

  /// A Write that created the file.
  final bool created;

  /// A Read of a file already read and unchanged since: its text is a note
  /// to the model, not the file.
  final bool unchanged;

  /// The tool's own timing (Glob, Agent, WebSearch).
  final int? durationMs;

  static ToolFacts from(Map structured) {
    String? str(String k) => structured[k] is String ? structured[k] as String : null;
    int? whole(Object? v) => v is num && v.isFinite ? v.toInt() : null;
    final file = structured['file'];
    int? added;
    int? removed;
    final patch = structured['structuredPatch'];
    if (patch is List) {
      added = 0;
      removed = 0;
      for (final hunk in patch) {
        final lines = hunk is Map ? hunk['lines'] : null;
        if (lines is! List) continue;
        for (final l in lines) {
          if (l is! String || l.isEmpty) continue;
          if (l[0] == '+') added = added! + 1;
          if (l[0] == '-') removed = removed! + 1;
        }
      }
    }
    final seconds = structured['durationSeconds'];
    return ToolFacts(
      stdout: str('stdout'),
      stderr: str('stderr'),
      interrupted: structured['interrupted'] == true,
      startLine: file is Map ? whole(file['startLine']) : null,
      numLines: file is Map ? whole(file['numLines']) : null,
      totalLines: file is Map ? whole(file['totalLines']) : null,
      linesAdded: added,
      linesRemoved: removed,
      created: structured['type'] == 'create',
      unchanged: structured['type'] == 'file_unchanged',
      durationMs: whole(structured['durationMs']) ??
          whole(structured['totalDurationMs']) ??
          (seconds is num ? (seconds * 1000).round() : null),
    );
  }
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

  /// Items built from `stream_event` deltas, by content block index within
  /// the current message.
  final Map<int, TranscriptItem> _liveBlocks = {};

  /// Every live item still shown.
  final Set<TranscriptItem> _live = Set.identity();

  List<TranscriptItem> get items => List.unmodifiable(_items);
  int get length => _items.length;

  /// When the frames being added arrived; null for a snapshot's, which
  /// arrived together long after they were written.
  DateTime? _at;

  /// Adds [frames]. [at] is when a live batch arrived on this device, for
  /// how long a tool call took when the frames don't say.
  void addFrames(Iterable<String> frames, {DateTime? at}) {
    _at = at;
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
      case 'stream_event':
        _streamEvent(f['event']);
      case 'assistant':
        if (f['partial'] == true) return;
        // The whole block: what streamed of it is replaced. Claude Code
        // writes it before the block's `content_block_stop`, and the next
        // block starts after that stop, so every live item is this block's.
        _dropLive(_live);
        final message = f['message'];
        if (message is Map) _assistant(message['content']);
      case 'user':
        if (f['isMeta'] == true) return;
        final message = f['message'];
        if (message is Map) _user(message['content'], f['tool_use_result']);
      case 'user_message':
        // AgentMux's own normalised record of a sent message.
        final m = f['message'];
        if (m is String && m.trim().isNotEmpty) {
          _items.add(PromptItem(_nextKey++, m));
        }
      case 'result':
        _dropLive(_live);
        _cancelRunning();
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
    // `system` (init), rate limits and the rest show nothing.
  }

  /// A raw API event inside a `stream_event` frame: reply text and thinking
  /// grow as they stream, as on the desktop. The
  /// `assistant` frame that follows each block replaces what streamed.
  void _streamEvent(Object? event) {
    if (event is! Map) return;
    final index = event['index'];
    switch (event['type']) {
      case 'message_start':
        // A new request: anything left streaming from the last one is stale.
        _dropLive(_live);
      case 'content_block_start':
        if (index is! int) return;
        final block = event['content_block'];
        if (block is! Map) return;
        switch (block['type']) {
          case 'text':
            final text = block['text'];
            _addLive(index, StreamingTextItem(_nextKey++, text is String ? text : ''));
          case 'thinking':
            final text = block['thinking'];
            _addLive(
              index,
              ThinkingItem(_nextKey++, text is String ? text : '').._streaming = true,
            );
        }
      case 'content_block_delta':
        if (index is! int) return;
        final delta = event['delta'];
        if (delta is! Map) return;
        switch (delta['type']) {
          case 'text_delta':
            final text = delta['text'];
            if (text is! String) return;
            final live = _liveBlocks[index];
            if (live is StreamingTextItem) {
              live.text += text;
            } else if (live == null) {
              // Its start came before what this device was sent.
              _addLive(index, StreamingTextItem(_nextKey++, text));
            }
          case 'thinking_delta':
            final text = delta['thinking'];
            if (text is! String) return;
            final live = _liveBlocks[index];
            if (live is ThinkingItem) {
              live.text += text;
            } else if (live == null) {
              _addLive(index, ThinkingItem(_nextKey++, text).._streaming = true);
            }
        }
    }
  }

  void _addLive(int index, TranscriptItem item) {
    _liveBlocks[index] = item;
    _live.add(item);
    _items.add(item);
  }

  /// Takes [which] live items off the screen.
  void _dropLive(Set<TranscriptItem> which) {
    if (which.isEmpty) return;
    final drop = Set<TranscriptItem>.identity()..addAll(which);
    _items.removeWhere(drop.contains);
    _live.removeAll(drop);
    _liveBlocks.removeWhere((_, item) => drop.contains(item));
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
          final input = block['input'];
          final summary = toolSummary(name, input);
          final existing = _tools[id];
          if (existing != null) {
            existing.summary = summary;
            if (input is Map<String, dynamic>) existing.input = input;
            continue;
          }
          final item = ToolCallItem(
            _nextKey++,
            id: id,
            name: name,
            summary: summary,
            input: input is Map<String, dynamic> ? input : null,
          )..receivedAt = _at;
          _tools[id] = item;
          _items.add(item);
        case 'thinking':
          final text = block['thinking'];
          if (text is String && text.trim().isNotEmpty) {
            _items.add(ThinkingItem(_nextKey++, text));
          }
        // `redacted_thinking` has nothing to show.
      }
    }
  }

  void _user(Object? content, Object? structured) {
    if (content is String) {
      if (content.trim().isNotEmpty) _items.add(PromptItem(_nextKey++, content));
      return;
    }
    if (content is! List) return;
    // Text-only arrays are Claude Code's meta lines; like the desktop pane,
    // only tool results are taken, and an interrupt ends what was running.
    final results = [
      for (final b in content)
        if (b is Map && b['type'] == 'tool_result') b,
    ];
    if (results.isEmpty) {
      final interrupted = content.any((b) =>
          b is Map &&
          b['text'] is String &&
          (b['text'] as String).startsWith('[Request interrupted by user'));
      if (interrupted) _cancelRunning();
      return;
    }
    for (final block in results) {
      final tool = _tools[block['tool_use_id']];
      if (tool == null) continue;
      final text = _resultText(block['content']);
      tool.state = block['is_error'] != true
          ? ToolState.done
          : (_denied(text) ? ToolState.denied : ToolState.failed);
      tool.result = _cap(text);
      // The structured result names no call: it is only this one's when
      // the message answers one call.
      if (results.length == 1 && structured is Map) {
        tool.facts = ToolFacts.from(structured);
      }
      tool.durationMs = _duration(tool);
    }
  }

  /// How long [tool] took: Bash's own `<exited N in Ts>` line, the tool's
  /// own timing, or the time between its call and result arriving live.
  int? _duration(ToolCallItem tool) {
    final bash = bashExit(tool.facts.stdout ?? tool.result);
    if (bash != null && bash.ms != null) return bash.ms;
    if (tool.facts.durationMs != null) return tool.facts.durationMs;
    final started = tool.receivedAt;
    final at = _at;
    if (started == null || at == null || !at.isAfter(started)) return null;
    return at.difference(started).inMilliseconds;
  }

  /// Claude Code's text for a call the user refused.
  static bool _denied(String text) =>
      text.startsWith("The user doesn't want to proceed with this tool use") ||
      text.contains('Permission to use') && text.contains('has been denied');

  void _cancelRunning() {
    for (final tool in _tools.values) {
      if (tool.state == ToolState.running) tool.state = ToolState.cancelled;
    }
  }

  static final _toolUseId = RegExp(r'"tool_use_id"\s*:\s*"([^"]{1,128})"');
  static final _toolUse = RegExp(
    r'"type"\s*:\s*"tool_use"\s*,\s*"id"\s*:\s*"([^"]{1,128})"\s*,\s*"name"\s*:\s*"([^"]{1,128})"',
  );
  static final _headPath = RegExp(r'"(?:file_path|notebook_path|path)"\s*:\s*"((?:[^"\\]|\\.){1,1024})"');

  /// A frame cut by the desktop: its head may still say which tool call it
  /// answers, or which call it is; otherwise it is shown on its own line.
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
        tool.durationMs = _duration(tool);
        return;
      }
      // A call too large to send (a big Write or Edit): its header is
      // still known from the head, which keeps its id and name first.
      final call = _toolUse.firstMatch(head);
      if (call != null && !head.contains('"parent_tool_use_id":"toolu')) {
        final callId = call.group(1)!;
        final name = call.group(2)!;
        final raw = _headPath.firstMatch(head)?.group(1);
        String? path;
        if (raw != null) {
          try {
            path = jsonDecode('"$raw"') as String;
          } on FormatException {
            path = null;
          }
        }
        final input = path == null ? null : <String, dynamic>{'file_path': path};
        final item = _tools[callId] ??
            (ToolCallItem(
              _nextKey++,
              id: callId,
              name: name,
              summary: toolSummary(name, input),
              input: input,
            )..receivedAt = _at);
        item.inputTruncatedBytes = bytes ?? 0;
        if (!_tools.containsKey(callId)) {
          _tools[callId] = item;
          _items.add(item);
        }
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

/// Bash's exit line, which AgentMux's bash wrapper puts before a command's
/// output: `<exited 0 in 0.60s>`.
class BashExit {
  const BashExit(this.code, this.ms, this.body);
  final int code;
  final int? ms;

  /// The output after the line.
  final String body;
}

/// Claude Code puts its own "Exit code N" line before a failed command's
/// output, so the wrapper's line may come second.
final _exitLine = RegExp(r'^(?:Exit code -?\d+\n)?<exited (-?\d+) in ([\d.]+)s>\n?');

/// The exit line at the start of [output], or null.
BashExit? bashExit(String? output) {
  if (output == null) return null;
  final m = _exitLine.firstMatch(output);
  if (m == null) return null;
  final seconds = double.tryParse(m[2]!);
  return BashExit(
    int.parse(m[1]!),
    seconds == null ? null : (seconds * 1000).round(),
    output.substring(m.end),
  );
}

String? _firstString(Map input) {
  for (final v in input.values) {
    if (v is String && v.trim().isNotEmpty) return v;
  }
  return null;
}
