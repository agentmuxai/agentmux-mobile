import 'package:agentmux_mobile/features/feed/feed_disclosure.dart';
import 'package:agentmux_mobile/features/feed/feed_theme.dart';
import 'package:agentmux_mobile/features/feed/messages.dart';
import 'package:agentmux_mobile/features/feed/notes_view.dart';
import 'package:agentmux_mobile/features/feed/transcript.dart';
import 'package:agentmux_mobile/features/feed/transcript_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'claude_fixtures.dart';

const _jekt = '''[JEKT:FROM=github-consumer TO=qtest TIER=coord DELIVERY=wan TRUST=network-claimed SIG=verified MSGID=inj-1 PRIORITY=urgent TS=1791936481]
────────────────────────────────────────────────────────────
From: github-consumer | To: qtest | ts=1791936481
[CI] PR #67 CI PASSED

Branch: qtest/feed-tool-calls
────────────────────────────────────────────────────────────
Reply: bus:inject to github-consumer
[/JEKT]''';

List<TranscriptItem> _items(List<String> frames) =>
    (Transcript(provider: 'claude')..addFrames(frames)).items;

String _system(String subtype, Map<String, Object?> rest) =>
    frame({'type': 'system', 'subtype': subtype, ...rest});

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('jekts', () {
    test('the marker and the body without its envelope', () {
      final j = parseJekt(_jekt)!;
      expect(j.from, 'github-consumer');
      expect(j.to, 'qtest');
      expect(j.tier, 'coord');
      expect(j.delivery, 'wan');
      expect(j.trust, 'network-claimed');
      expect(j.fields['SIG'], 'verified');
      expect(j.priority, 'urgent');
      expect(j.sentAt, DateTime.fromMillisecondsSinceEpoch(1791936481000));
      expect(j.body, '[CI] PR #67 CI PASSED\n\nBranch: qtest/feed-tool-calls');
    });

    test('no FROM or TO is not a jekt; a missing tier is sensitive', () {
      expect(parseJekt('[JEKT:TO=x]\nhi\n[/JEKT]'), isNull);
      expect(parseJekt('[JEKT:FROM=a TO=b]\nhi\n[/JEKT]')!.sensitive, isTrue);
      expect(parseJekt('see [JEKT:FROM=a TO=b]\nhi\n[/JEKT]'), isNull);
    });

    test('a user turn that is a jekt is a jekt row', () {
      expect(_items([userPrompt(_jekt)]).single, isA<JektItem>());
    });
  });

  test('broadcasts: only from the user via Swarm', () {
    final b = parseBroadcast('[BROADCAST:FROM=user VIA=swarm TO=qtest RECIPIENTS=3 MSGID=m TS=1]\nRun the tests')!;
    expect(b.recipients, 3);
    expect(b.body, 'Run the tests');
    expect(broadcastNote(3), 'Broadcast · 3 agents');
    expect(broadcastNote(1), 'Broadcast');
    expect(parseBroadcast('[BROADCAST:FROM=agent VIA=swarm]\nx'), isNull);
    final p = _items([userPrompt('[BROADCAST:FROM=user VIA=swarm TO=q RECIPIENTS=3]\nRun the tests')]).single as PromptItem;
    expect(p.broadcast, isTrue);
    expect(p.text, 'Run the tests');
  });

  test('a reinjection, a continuation and the user\'s words are three rows', () {
    const text = '<system-reminder>\n$reinjectionSignature\n\n# Global Memory (17 entries)\na\n---\nb\n'
        '# Personal Memory (2 entries)\nc\n</system-reminder>\n'
        '<agentmux-continuation>\n## Running summary\nDid things.\n</agentmux-continuation>\n\n'
        'ok lets implement the full look on mobile';
    final items = _items([userPrompt(text)]);
    expect(items.map((i) => i.runtimeType), [PromptItem, ContextItem, ContextItem]);
    expect((items[0] as PromptItem).text, 'ok lets implement the full look on mobile');
    final memory = items[1] as ContextItem;
    expect(memory.kind, ContextKind.memory);
    expect((memory.globalCount, memory.personalCount), (17, 2));
    expect(contextSummary(memory), startsWith('🧠 Memory reinjected — 17 global, 2 personal (~'));
    expect((items[2] as ContextItem).kind, ContextKind.continuation);
  });

  test('a plain reminder is its own row, never inside the prompt', () {
    final items = _items([userPrompt('Fix it\n<system-reminder>\nThe date changed.\n</system-reminder>')]);
    expect((items[0] as PromptItem).text, 'Fix it');
    final r = items[1] as ContextItem;
    expect(r.kind, ContextKind.systemReminder);
    expect(r.text, 'The date changed.');
  });

  test('the startup context is one row', () {
    final c = _items([userPrompt('# Session Context\n\nYou are QTest.')]).single as ContextItem;
    expect(c.kind, ContextKind.sessionContext);
  });

  test('attachments are named, not shown as text', () {
    const text = 'Look at these\n\n<attached_files>\n1. /tmp/a/report.pdf — report.pdf [from Slack]\n'
        '- old.png — (no longer available)\n</attached_files>';
    final (body, names) = splitAttachments(text);
    expect(body, 'Look at these');
    expect(names, ['report.pdf', 'old.png (no longer available)']);
  });

  test('a prompt with an image names the image', () {
    final p = _items([
      frame({
        'type': 'user',
        'message': {
          'content': [
            {'type': 'text', 'text': 'What is this?'},
            {'type': 'image', 'source': {'type': 'base64', 'data': 'x'}},
          ],
        },
      }),
    ]).single as PromptItem;
    expect(p.text, 'What is this?');
    expect(p.attachments, ['Image 1']);
  });

  String imageTurn(List<Map<String, Object?>> text) => frame({
        'type': 'user',
        'message': {
          'content': [
            ...text,
            {'type': 'image', 'source': {'type': 'base64', 'data': 'x'}},
          ],
        },
      });

  test('an image-only prompt is its own prompt, not the one before it', () {
    final items = _items([userPrompt('First'), imageTurn([])]);
    expect(items.map((i) => (i as PromptItem).text), ['First', '']);
    expect((items[0] as PromptItem).attachments, isEmpty);
    expect((items[1] as PromptItem).attachments, ['Image 1']);
  });

  test('an image beside a reminder stays on its prompt', () {
    final items = _items([
      imageTurn([
        {'type': 'text', 'text': 'Look\n<system-reminder>\nx\n</system-reminder>'},
      ]),
    ]);
    expect(items.map((i) => i.runtimeType), [PromptItem, ContextItem]);
    expect((items[0] as PromptItem).attachments, ['Image 1']);
  });

  group('compaction', () {
    test('compacting, then the divider, then the summary card', () {
      final t = Transcript(provider: 'claude')
        ..addFrames([_system('status', {'status': 'compacting'})]);
      expect((t.items.single as NoticeItem).label, 'Compacting conversation…');
      t.addFrames([
        _system('compact_boundary', {
          'compact_metadata': {'trigger': 'auto', 'pre_tokens': 150000, 'post_tokens': 9000, 'duration_ms': 41000},
        }),
        frame({
          'type': 'user',
          'isSynthetic': true,
          'message': {'content': '$compactSummaryLead that ran out of context.\n\nSummary:\n1. The user asked for the phone feed.'},
        }),
      ]);
      expect(t.items.map((i) => i.runtimeType), [NoticeItem, ContextItem]);
      final d = t.items.first as NoticeItem;
      expect(d.label, 'Context compacted — auto-compacted');
      expect(d.detail, 'Earlier history summarized · 150.0k tokens summarized to 9.0k · took 41.0s');
      final s = t.items.last as ContextItem;
      expect(s.kind, ContextKind.compactSummary);
      expect(compactExcerpt(s.text), '1. The user asked for the phone feed.');
    });

    test('without a boundary, the lead alone is a prompt', () {
      expect(_items([userPrompt('$compactSummaryLead, as I said')]).single, isA<PromptItem>());
    });
  });

  group('AgentMux notes', () {
    test('session outcome, version change, failed compaction', () {
      final items = _items([
        _system('agentmux_session_outcome', {'outcome': 'fresh', 'continued': true}),
        _system('agentmux_session_outcome', {'outcome': 'resumed'}),
        _system('agentmux_cli_version_changed', {'provider': 'claude', 'from': '2.1.1', 'to': '2.1.2', 'pinned': '2.1.1'}),
        _system('status', {'compact_result': 'failed', 'compact_error': 'Error during compaction: too long'}),
        _system('init', {'session_id': 's'}),
      ]).cast<NoticeItem>();
      expect(items.map((n) => n.label), [
        'Session continued · reconstructed context',
        'Claude Code updated: 2.1.1 → 2.1.2',
        "Claude Code couldn't compact the conversation",
      ]);
      expect(items.map((n) => n.tone), [NoticeTone.warn, NoticeTone.warn, NoticeTone.error]);
      expect(items.elementAt(1).detail, 'Not the version AgentMux pins (2.1.1)');
      expect(items.last.detail, 'too long');
    });

    test('a context delivery card', () {
      final d = _items([
        _system('agentmux_memory_injected', {
          'reason': 'startup',
          'entries': [
            {'label': '[AgentMux System] MuxAPI', 'source': 'global', 'tokens': 900},
            {'label': 'notes', 'source': 'personal', 'tokens': 100, 'delivered': 'partial'},
          ],
        }),
      ]).single as DeliveryItem;
      expect(d.title, 'Given to the agent · new session · 2 items · 1 cut');
      expect(d.entries.map((e) => (e.icon, e.name, e.chip)), [
        ('🌐', 'MuxAPI', 'AgentMux system'),
        ('👤', 'notes', 'Personal'),
      ]);
    });
  });

  test('an error: its HTTP status and message', () {
    final items = _items([
      frame({'type': 'result', 'is_error': true, 'api_error_status': 401, 'error': {'message': 'Invalid API key'}}),
    ]);
    final e = items.first as ErrorItem;
    expect(e.code, 401);
    expect(e.message, 'Invalid API key');
    expect(items, hasLength(1));
  });

  test('an answered question: the question and the answer', () {
    final t = ToolCallItem(0, id: 't', name: 'AskUserQuestion', input: {
      'questions': [
        {'question': 'Which theme?', 'options': []},
      ],
    })
      ..state = ToolState.done
      ..result = 'User has answered your questions: "Which theme?"="Dark". You can now continue.';
    final qa = answeredQuestion(t)!;
    expect(qa.question, 'Which theme?');
    expect(qa.answer, 'Dark');
  });

  group('disclosure', () {
    test('sensitive jekts start open, others closed; reminders closed', () {
      final d = FeedDisclosure();
      final sensitive = JektItem(1, parseJekt('[JEKT:FROM=a TO=b TIER=sensitive]\nx\n[/JEKT]')!);
      final coord = JektItem(2, parseJekt(_jekt)!);
      final reminder = ContextItem(3, ContextKind.systemReminder, 'x');
      expect(d.isOpen(sensitive), isTrue);
      expect(d.isOpen(coord), isFalse);
      expect(d.isOpen(reminder), isFalse);
      d.toggle(reminder);
      expect(d.isOpen(reminder), isTrue);
      d.hold(coord.key);
      expect(d.isOpen(coord), isTrue);
    });
  });

  group('rows', () {
    testWidgets('a reminder is one collapsed line that opens', (tester) async {
      var open = false;
      await tester.pumpWidget(StatefulBuilder(
        builder: (_, set) => _host(TranscriptItemView(
          item: ContextItem(0, ContextKind.systemReminder, 'The date changed.'),
          expanded: open,
          onToggle: () => set(() => open = !open),
        )),
      ));
      expect(find.text('System reminder'), findsOneWidget);
      expect(find.text('The date changed.'), findsNothing);
      await tester.tap(find.text('System reminder'));
      await tester.pump();
      expect(find.text('The date changed.'), findsOneWidget);
    });

    testWidgets('a jekt line: sender, tier and delivery; opened, its marker', (tester) async {
      await tester.pumpWidget(_host(TranscriptItemView(item: JektItem(0, parseJekt(_jekt)!), expanded: true)));
      expect(find.text('🔗 coord'), findsOneWidget);
      expect(find.text('☁️ wan'), findsOneWidget);
      expect(find.textContaining('From github-consumer', findRichText: true), findsOneWidget);
      expect(find.textContaining('MSGID: inj-1'), findsOneWidget);
      expect(find.textContaining('Sig: verified'), findsOneWidget);
      expect(find.text('▸ Raw payload'), findsOneWidget);
    });

    testWidgets('a broadcast prompt has its note; attachments are named', (tester) async {
      await tester.pumpWidget(_host(TranscriptItemView(
        item: PromptItem(0, 'Run the tests', broadcast: true, recipients: 3, attachments: ['a.png']),
      )));
      expect(find.text('📣 Broadcast · 3 agents'), findsOneWidget);
      expect(find.text('📎 a.png'), findsOneWidget);
    });

    testWidgets('an error block: HTTP status, message, red bar', (tester) async {
      await tester.pumpWidget(_host(TranscriptItemView(item: ErrorItem(0, 'Invalid API key', code: 401))));
      expect(find.text('HTTP 401'), findsOneWidget);
      expect(find.text('Invalid API key'), findsOneWidget);
      final box = tester.widget<Container>(find.descendant(of: find.byType(ErrorBlock), matching: find.byType(Container)).first);
      expect(((box.decoration! as BoxDecoration).border! as Border).left.color, FeedColors.error);
    });

    testWidgets('a notice is a divider with its label and detail', (tester) async {
      await tester.pumpWidget(_host(TranscriptItemView(
        item: NoticeItem(0, 'New session started', detail: 'Above is gone', tone: NoticeTone.warn),
      )));
      final label = tester.widget<Text>(find.text('New session started'));
      expect(label.style?.color, FeedColors.warningText);
      expect(find.text('Above is gone'), findsOneWidget);
    });
  });

  test('every desktop harness has a display name', () {
    expect(providerName('claude'), 'Claude Code');
    expect(providerName('opencode'), 'OpenCode');
    expect(providerName('dsh'), 'DeepSeek Harness');
    expect(providerName('muse'), 'Muse Code');
    expect(providerName('agy'), 'Antigravity');
    // Unknown ids still show as given; an empty one reads as the agent.
    expect(providerName('newcli'), 'newcli');
    expect(providerName(''), 'The agent');
  });
}
