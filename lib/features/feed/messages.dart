/// Recognising what in a transcript isn't the user's own words, by the
/// desktop agent pane's rules (`stream-parser.ts`, `memory-reinjection.ts`,
/// `attachments/attached-images.ts`, `cli-notice.ts`;
/// `SPEC_FEED_RENDERS_LIKE_THE_DESKTOP_PANE_2026_10_13.md` §7). Pure: the
/// transcript turns these into items.
library;

/// A message from another agent, as AgentMux wraps it. The phone shows the
/// marker; it never acts on it.
class Jekt {
  const Jekt({
    required this.from,
    required this.to,
    required this.tier,
    required this.delivery,
    required this.trust,
    required this.msgId,
    required this.priority,
    required this.body,
    required this.raw,
    this.sentAt,
    this.fields = const {},
  });
  final String from;
  final String to;

  /// `info`, `coord` or `sensitive`.
  final String tier;

  /// `host`, `lan`, `wan` or `channel`.
  final String delivery;

  /// The marker's `TRUST=`, as written.
  final String trust;
  final String msgId;

  /// `urgent` or `normal`.
  final String priority;
  final DateTime? sentAt;

  /// The message without its envelope lines.
  final String body;

  /// The whole message, as received.
  final String raw;

  /// Every field of the marker.
  final Map<String, String> fields;

  bool get sensitive => tier == 'sensitive';
}

final _jektBlock = RegExp(r'^\[JEKT:([^\]\n]+)\]\r?\n([\s\S]*?)\r?\n\[/JEKT\]\s*$');
final _field = RegExp(r'(\w+)=(\S+)');

Map<String, String> _fields(String marker) => {
      for (final m in _field.allMatches(marker)) m[1]!: m[2]!,
    };

/// [text] as a jekt, when the whole of it is one; FROM and TO are required.
Jekt? parseJekt(String text) {
  final t = text.trim();
  final m = _jektBlock.firstMatch(t);
  if (m == null) return null;
  final f = _fields(m[1]!);
  final from = f['FROM'];
  final to = f['TO'];
  if (from == null || to == null) return null;
  const tiers = {'info', 'coord', 'sensitive'};
  const deliveries = {'host', 'lan', 'wan', 'channel'};
  final tier = tiers.contains(f['TIER']) ? f['TIER']! : 'sensitive';
  final ts = int.tryParse(f['TS'] ?? '');
  return Jekt(
    from: from,
    to: to,
    tier: tier,
    delivery: deliveries.contains(f['DELIVERY']) ? f['DELIVERY']! : 'wan',
    trust: f['TRUST'] ?? 'network-claimed',
    msgId: f['MSGID'] ?? '',
    priority: f['PRIORITY'] == 'urgent' ? 'urgent' : 'normal',
    sentAt: ts == null ? null : DateTime.fromMillisecondsSinceEpoch(ts * 1000),
    body: _jektBody(m[2]!, sensitive: tier == 'sensitive'),
    raw: t,
    fields: f,
  );
}

/// The envelope lines AgentMux puts around a jekt's body, at their fixed
/// places (`stripJektEnvelope`).
String _jektBody(String inner, {required bool sensitive}) {
  final lines = inner.split(RegExp(r'\r?\n'));
  var start = 0;
  if (start < lines.length && RegExp(r'^─+$').hasMatch(lines[start])) start++;
  if (start < lines.length && RegExp(r'^From:.*\|.*\|').hasMatch(lines[start])) start++;
  if (sensitive && start < lines.length && lines[start].startsWith('⚠')) {
    start++;
    if (start < lines.length && lines[start].trim().isEmpty) start++;
  }
  var end = lines.length;
  if (end > start && lines[end - 1].startsWith('Reply:')) end--;
  if (end > start && RegExp(r'^─+$').hasMatch(lines[end - 1])) end--;
  return lines.sublist(start, end).join('\n').trim();
}

const jektTierIcons = {'info': 'ℹ️', 'coord': '🔗', 'sensitive': '⚠️'};
const jektDeliveryIcons = {'host': '🏠', 'lan': '🛰️', 'wan': '☁️', 'channel': '🔀'};

/// A Swarm broadcast: the operator typed it once for several agents.
class Broadcast {
  const Broadcast(this.recipients, this.body);

  /// How many agents got it; null when the header doesn't say.
  final int? recipients;
  final String body;
}

final _broadcastHeader = RegExp(r'^\[BROADCAST:([^\]\n]+)\]\r?\n([\s\S]*)$');

Broadcast? parseBroadcast(String text) {
  final m = _broadcastHeader.firstMatch(text);
  if (m == null) return null;
  final f = _fields(m[1]!);
  if (f['FROM'] != 'user' || f['VIA'] != 'swarm') return null;
  final n = int.tryParse(f['RECIPIENTS'] ?? '');
  return Broadcast(n != null && n > 0 ? n : null, m[2]!);
}

/// "Broadcast · 3 agents".
String broadcastNote(int? recipients) =>
    recipients != null && recipients > 1 ? 'Broadcast · $recipients agents' : 'Broadcast';

/// The note over a message a paired phone sent.
String fromDeviceNote(String device) => 'From $device';

/// The context AgentMux gives an agent when it starts.
bool isSessionContext(String text) => RegExp(r'^# Session Context\b').hasMatch(text);

/// A block AgentMux or Claude Code puts inside a user turn.
enum WrapperKind { systemReminder, continuation }

class Wrapper {
  const Wrapper(this.kind, this.text);
  final WrapperKind kind;

  /// The block's content, without its tags.
  final String text;
}

final _wrapper = RegExp(
  r'<(system-reminder|agentmux-continuation)>\r?\n?([\s\S]*?)\r?\n?</\1>',
);

/// [text] without its `<system-reminder>` and `<agentmux-continuation>`
/// blocks, and the blocks, in order.
(String, List<Wrapper>) splitWrappers(String text) {
  if (!text.contains('<system-reminder>') && !text.contains('<agentmux-continuation>')) {
    return (text, const []);
  }
  final blocks = <Wrapper>[];
  final rest = text.replaceAllMapped(_wrapper, (m) {
    blocks.add(Wrapper(
      m[1] == 'system-reminder' ? WrapperKind.systemReminder : WrapperKind.continuation,
      m[2]!.trim(),
    ));
    return '';
  });
  return (rest.trim(), blocks);
}

/// AgentMux's memory reinjection reminder (`memory-reinjection.ts`).
const reinjectionSignature =
    'Your memory was reinjected because your working context was just reset.';

/// The counts of a memory reinjection's Global and Personal Memory entries,
/// from the headings AgentMux writes; null when [reminder] isn't one.
({int global, int personal})? memoryCounts(String reminder) {
  if (!reminder.contains(reinjectionSignature)) return null;
  int count(String heading) {
    final m = RegExp('# $heading Memory \\((\\d+) entr(?:y|ies)\\)').firstMatch(reminder);
    return m == null ? 0 : int.parse(m[1]!);
  }

  return (global: count('Global'), personal: count('Personal'));
}

/// An estimate of how many tokens [text] is, as the desktop labels it.
int estimateTokens(String text) => (text.length / 4).ceil();

/// `812`, `4.2k`, `1.3M`.
String formatTokens(int n) {
  if (n < 1000) return '$n';
  if (n < 1000000) return '${(n / 1000).toStringAsFixed(1)}k';
  return '${(n / 1000000).toStringAsFixed(1)}M';
}

final _attachments = RegExp(r'\n*<(attached_files|attached_images)>\n([\s\S]*?)\n?</\1>\s*$');
final _attachedFound = RegExp(r'^(\d+)\. (.*) — (.+)$');
final _attachedMissing = RegExp(r'^- (.*) — \(no longer available\)$');

/// [text] without the attachment block AgentMux adds at its end, and the
/// attached files' names.
(String, List<String>) splitAttachments(String text) {
  final names = <String>[];
  var rest = text;
  // A message may carry both blocks, files and images.
  for (var i = 0; i < 2; i++) {
    final m = _attachments.firstMatch(rest);
    if (m == null) break;
    final found = <String>[];
    for (final line in m[2]!.split('\n')) {
      final f = _attachedFound.firstMatch(line);
      final missing = _attachedMissing.firstMatch(line);
      // "1. <path> — <name>": the name is what the user knows it by.
      final name = f?[3] ?? missing?[1];
      if (name == null) continue;
      final clean = name.replaceFirst(RegExp(r' \[[^\]]*\]$'), '');
      found.add(missing == null ? clean : '$clean (no longer available)');
    }
    names.insertAll(0, found);
    rest = rest.substring(0, m.start);
  }
  return (rest, names);
}

/// Claude Code's summary after a compaction, as a user turn.
const compactSummaryLead = 'This session is being continued from a previous conversation';

/// The summary card's one-line excerpt: its first line that says something.
String compactExcerpt(String text) {
  for (final raw in text.split('\n')) {
    final l = raw.trim();
    if (l.isEmpty || l.startsWith(compactSummaryLead) || l.endsWith(':') || l.startsWith('#')) {
      continue;
    }
    return l.length <= 160 ? l : '${l.substring(0, 160)}…';
  }
  return '';
}

/// How an AgentMux note reads.
enum NoticeTone { info, warn, error }

/// What an AgentMux `system` frame says, or null when it isn't one the feed
/// shows (`cli-notice.ts`, `session-outcome.ts`).
({String label, String? detail, NoticeTone tone})? systemNotice(Map f, String provider) {
  final name = providerName(f['provider'] is String ? f['provider'] as String : provider);
  String? s(String k) => f[k] is String && (f[k] as String).isNotEmpty ? f[k] as String : null;
  switch (f['subtype']) {
    case 'status' when f['compact_result'] == 'failed':
      final err = s('compact_error')?.replaceFirst('Error during compaction: ', '');
      return (label: "$name couldn't compact the conversation", detail: err, tone: NoticeTone.error);
    case 'agentmux_cli_install':
      final v = s('version') ?? '';
      return switch (f['state']) {
        'installing' => (
            label: 'Installing $name $v…',
            detail: "The agent starts once it's installed",
            tone: NoticeTone.info,
          ),
        'installed' => (
            label: 'Installed $name $v${f['seconds'] is num ? ' (${(f['seconds'] as num).round().clamp(1, 1 << 30)} s)' : ''}',
            detail: null,
            tone: NoticeTone.info,
          ),
        _ => (label: "Couldn't install $name $v", detail: s('error'), tone: NoticeTone.error),
      };
    case 'agentmux_cli_version_changed':
      final from = s('from');
      final to = s('to');
      if (from == null || to == null) return null;
      final pinned = s('pinned');
      final offPin = pinned != null && pinned != to;
      return (
        label: '$name updated: $from → $to',
        detail: offPin ? 'Not the version AgentMux pins ($pinned)' : null,
        tone: offPin ? NoticeTone.warn : NoticeTone.info,
      );
    case 'agentmux_mcp_health':
      final err = s('error');
      return switch (f['state']) {
        'healing' => (
            label: "AgentMux tools didn't connect. Reconnecting (try ${f['step'] is num ? f['step'] : 1} of 2)…",
            detail: err,
            tone: NoticeTone.warn,
          ),
        'restarting' => (
            label: "AgentMux tools still aren't connected. Restarting the agent without the shell prefix…",
            detail: err,
            tone: NoticeTone.warn,
          ),
        'ok' => (
            label: 'AgentMux tools are connected again',
            detail: f['safe_profile'] == true ? 'Running without the shell prefix until AgentMux restarts' : null,
            tone: NoticeTone.info,
          ),
        'gave_up' => (
            label: "AgentMux tools aren't connected, and AgentMux couldn't repair them",
            detail: [if (err != null) err, 'The agent was told to run `agentmux-mcp doctor`.'].join('. '),
            tone: NoticeTone.error,
          ),
        _ => null,
      };
    case 'agentmux_session_outcome':
      if (f['outcome'] != 'fresh') return null;
      return f['continued'] == true
          ? (
              label: 'Session continued · reconstructed context',
              detail: "The provider couldn't resume the previous session, so this new one was given "
                  "AgentMux's record of the conversation: a running summary and the recent exchange",
              tone: NoticeTone.warn,
            )
          : (
              label: 'New session started',
              detail: "The agent doesn't have the conversation above this line",
              tone: NoticeTone.warn,
            );
  }
  return null;
}

String providerName(String provider) {
  final p = provider.toLowerCase();
  if (p.startsWith('claude')) return 'Claude Code';
  if (p.startsWith('qwen')) return 'Qwen Code';
  if (p.startsWith('codex')) return 'Codex';
  if (p.startsWith('gemini')) return 'Gemini CLI';
  // The desktop app's other harness ids (its providers/catalog.ts).
  const names = {
    'antigravity': 'Antigravity',
    'agy': 'Antigravity',
    'kimi': 'Kimi Code',
    'pi': 'Pi',
    'openclaw': 'OpenClaw',
    'copilot': 'GitHub Copilot CLI',
    'muxcode': 'Mux Code',
    'kilo': 'Kilo Code CLI',
    'cline': 'Cline CLI',
    'opencode': 'OpenCode',
    'goose': 'goose',
    'grok': 'Grok Build',
    'dsh': 'DeepSeek Harness',
    'aider': 'Aider',
    'crush': 'Crush',
    'muse': 'Muse Code',
  };
  return names[p] ?? (provider.isEmpty ? 'The agent' : provider);
}

/// The compaction divider: "Context compacted — auto-compacted", and what
/// it did.
({String label, String? detail}) compactBoundary(Map f) {
  final meta = f['compact_metadata'] ?? f['compactMetadata'];
  int? n(String snake, String camel) {
    final v = meta is Map ? (meta[snake] ?? meta[camel]) : null;
    return v is num ? v.toInt() : null;
  }

  final trigger = meta is Map ? meta['trigger'] : null;
  final pre = n('pre_tokens', 'preTokens');
  final post = n('post_tokens', 'postTokens');
  final ms = n('duration_ms', 'durationMs');
  final parts = [
    'Earlier history summarized',
    if (pre != null && post != null) '${formatTokens(pre)} tokens summarized to ${formatTokens(post)}',
    if (ms != null) 'took ${(ms / 1000).toStringAsFixed(1)}s',
  ];
  return (
    label: 'Context compacted — ${trigger == 'manual' ? 'you ran /compact' : 'auto-compacted'}',
    detail: parts.join(' · '),
  );
}

/// One thing AgentMux gave the agent (`agentmux_memory_injected`).
class Delivered {
  const Delivered({required this.icon, required this.name, required this.chip, this.cut = false, this.tokens = 0});
  final String icon;
  final String name;
  final String chip;
  final bool cut;
  final int tokens;
}

/// The context delivery card's title and rows, from its frame
/// (`memory-injected.ts`, `context-delivery.ts`).
({String title, List<Delivered> items})? contextDelivery(Map f) {
  final entries = f['entries'];
  if (entries is! List) return null;
  const memoryKinds = {'global_memory', 'personal_memory', 'running_summary'};
  final items = <Delivered>[];
  var allMemory = true;
  var cut = 0;
  for (final e in entries) {
    if (e is! Map) continue;
    final label = e['label'] is String ? e['label'] as String : '';
    final kind = e['kind'] is String
        ? e['kind'] as String
        : (e['source'] == 'personal'
            ? 'personal_memory'
            : (e['source'] == 'summary' ? 'running_summary' : 'global_memory'));
    if (!memoryKinds.contains(kind)) allMemory = false;
    var name = e['name'] is String ? e['name'] as String : label;
    var chip = switch (kind) {
      'personal_memory' => 'Personal',
      'running_summary' => 'Summary',
      'startup_file' => 'Startup file',
      _ => 'Global',
    };
    if (label.startsWith('[AgentMux System] ')) {
      name = label.substring('[AgentMux System] '.length);
      chip = 'AgentMux system';
    } else if (label.startsWith('[Workspace] ')) {
      name = label.substring('[Workspace] '.length);
      chip = 'Workspace';
    }
    final isCut = e['delivered'] == 'partial' || e['delivered'] == 'omitted';
    if (isCut) cut++;
    items.add(Delivered(
      icon: switch (kind) {
        'personal_memory' => '👤',
        'running_summary' => '🧭',
        'startup_file' => '📄',
        _ => '🌐',
      },
      name: name,
      chip: chip,
      cut: isCut,
      tokens: e['tokens'] is num ? (e['tokens'] as num).toInt() : 0,
    ));
  }
  final n = items.length;
  final count = '$n ${n == 1 ? 'item' : 'items'}${cut > 0 ? ' · $cut cut' : ''}';
  final reason = f['reason'];
  final String title;
  if (reason == 'compact' && allMemory) {
    title = 'Memory re-delivered after compaction · $count';
  } else {
    final when = switch (reason) {
      'clear' => 'after /clear',
      'compact' => 'after compaction',
      'resume_fresh' => 'session continued',
      _ => 'new session',
    };
    title = 'Given to the agent · $when · $count';
  }
  return (title: title, items: items);
}
