import 'package:agentmux_mobile/features/feed/feed_theme.dart';
import 'package:agentmux_mobile/features/feed/line_diff.dart';
import 'package:agentmux_mobile/features/feed/tool_block.dart';
import 'package:agentmux_mobile/features/feed/feed_disclosure.dart';
import 'package:agentmux_mobile/features/feed/tool_meta.dart';
import 'package:agentmux_mobile/features/feed/transcript.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'claude_fixtures.dart';

/// A tool call answered by [result], with Claude Code's structured result.
List<String> _call(
  String name,
  Map<String, Object?> input,
  Object result, {
  Map<String, Object?>? structured,
  bool isError = false,
}) =>
    [
      toolUse('toolu_x', name, input),
      frame({
        'type': 'user',
        'message': {
          'role': 'user',
          'content': [
            {
              'type': 'tool_result',
              'tool_use_id': 'toolu_x',
              'content': result,
              if (isError) 'is_error': true,
            },
          ],
        },
        if (structured != null) 'tool_use_result': structured,
      }),
    ];

ToolCallItem _tool(List<String> frames, {DateTime? at}) =>
    (Transcript(provider: 'claude')..addFrames(frames, at: at)).items.whereType<ToolCallItem>().single;

ToolCallItem _item(String name, Map<String, dynamic> input,
    {ToolState state = ToolState.done, String? result, int key = 0}) {
  return ToolCallItem(key, id: 't$key', name: name, input: input)
    ..state = state
    ..result = result;
}

Widget _host(Widget child, {double width = 400}) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, child: SingleChildScrollView(child: child)),
        ),
      ),
    );

String _allText(WidgetTester tester) {
  final b = StringBuffer();
  for (final w in tester.widgetList(find.byWidgetPredicate((w) => w is Text || w is SelectableText))) {
    if (w is Text) b.writeln(w.textSpan?.toPlainText() ?? w.data);
    if (w is SelectableText) b.writeln(w.textSpan?.toPlainText() ?? w.data);
  }
  return b.toString();
}

void main() {
  group('transcript', () {
    test('a call keeps its input', () {
      final t = _tool([toolUse('toolu_x', 'Edit', {'file_path': 'a.dart', 'old_string': 'a', 'new_string': 'b'})]);
      expect(t.input['old_string'], 'a');
      expect(t.state, ToolState.running);
    });

    test('Bash: the exit line gives the duration; stdout and stderr kept', () {
      final t = _tool(_call(
        'Bash',
        {'command': 'make'},
        '<exited 2 in 1.25s>\nbuilding\nerror: no rule',
        structured: {'stdout': '<exited 2 in 1.25s>\nbuilding', 'stderr': 'error: no rule', 'interrupted': false},
      ));
      expect(t.durationMs, 1250);
      expect(t.facts.stdout, '<exited 2 in 1.25s>\nbuilding');
      expect(t.facts.stderr, 'error: no rule');
      final exit = bashExit(t.facts.stdout)!;
      expect(exit.code, 2);
      expect(exit.body, 'building');
    });

    test('a failed Bash: Claude Code\'s "Exit code N" line comes first', () {
      final t = _tool(_call(
        'Bash',
        {'command': 'ls /nonexistent'},
        "Exit code 2\n<exited 2 in 0.38s>\nls: cannot access '/nonexistent'",
        isError: true,
      ));
      expect(t.state, ToolState.failed);
      expect(t.durationMs, 380);
      expect(toolPill(t)!.label, 'exit 2');
      expect(bashExit(t.result)!.body, "ls: cannot access '/nonexistent'");
    });

    test('Read: the range from the structured result', () {
      final t = _tool(_call(
        'Read',
        {'file_path': 'lib/a.dart'},
        '   120\tline',
        structured: {
          'type': 'text',
          'file': {'filePath': 'lib/a.dart', 'content': 'line', 'startLine': 120, 'numLines': 60, 'totalLines': 456},
        },
      ));
      expect(readRange(t), '120:179 of 456');
    });

    test('Edit: the changed lines from the patch', () {
      final t = _tool(_call(
        'Edit',
        {'file_path': 'a.dart', 'old_string': 'a', 'new_string': 'b\nc'},
        'The file a.dart has been updated.',
        structured: {
          'structuredPatch': [
            {'oldStart': 3, 'newStart': 3, 'lines': [' x', '-a', '+b', '+c', ' y']},
          ],
        },
      ));
      expect(t.facts.linesAdded, 2);
      expect(t.facts.linesRemoved, 1);
      expect(toolPill(t)!.label, '3 lines');
    });

    test('several results in one message: the structured result is no one\'s', () {
      final frames = [
        toolUse('toolu_a', 'Bash', {'command': 'a'}),
        toolUse('toolu_b', 'Bash', {'command': 'b'}),
        frame({
          'type': 'user',
          'message': {
            'content': [
              {'type': 'tool_result', 'tool_use_id': 'toolu_a', 'content': 'A'},
              {'type': 'tool_result', 'tool_use_id': 'toolu_b', 'content': 'B'},
            ],
          },
          'tool_use_result': {'stdout': 'B', 'stderr': ''},
        }),
      ];
      final tools = (Transcript(provider: 'claude')..addFrames(frames)).items.whereType<ToolCallItem>();
      expect(tools.map((t) => t.facts.stdout), [null, null]);
    });

    test('a live call\'s duration is the time between call and result', () {
      final t0 = DateTime(2026, 10, 13, 12);
      final tr = Transcript(provider: 'claude')
        ..addFrames([toolUse('toolu_x', 'Grep', {'pattern': 'x'})], at: t0)
        ..addFrames(_call('Grep', {}, 'Found 1 file').skip(1), at: t0.add(const Duration(milliseconds: 2300)));
      expect((tr.items.single as ToolCallItem).durationMs, 2300);
    });

    test('a snapshot\'s calls have no measured duration', () {
      expect(_tool(_call('Grep', {'pattern': 'x'}, 'Found 1 file')).durationMs, isNull);
    });

    test('a refused call is denied', () {
      final t = _tool(_call(
        'Bash',
        {'command': 'rm x'},
        "The user doesn't want to proceed with this tool use. The tool use was rejected.",
        isError: true,
      ));
      expect(t.state, ToolState.denied);
      expect(toolGlyph(t), '⊘');
    });

    test('an interrupt or the turn\'s end cancels what is running', () {
      final tr = Transcript(provider: 'claude')
        ..addFrames([
          toolUse('toolu_x', 'Bash', {'command': 'sleep 99'}),
          frame({
            'type': 'user',
            'message': {
              'content': [
                {'type': 'text', 'text': '[Request interrupted by user for tool use]'},
              ],
            },
          }),
        ]);
      final t = tr.items.first as ToolCallItem;
      expect((tr.items.last as NoticeItem).label, '⏹ Interrupted by user');
      expect(t.state, ToolState.cancelled);
      expect(toolGlyph(t), '⏹');
    });

    test('a call too large to send still gets its header', () {
      final whole = toolUse('toolu_big', 'Write', {'file_path': r'C:\x\big.json', 'content': 'y' * 1000});
      final tr = Transcript(provider: 'claude')..addFrames([truncated(whole.substring(0, 300), 90000)]);
      final t = tr.items.single as ToolCallItem;
      expect(t.name, 'Write');
      expect(t.inputTruncatedBytes, 90000);
      expect(t.input['file_path'], r'C:\x\big.json');
      expect(buildPreview(t).child, isA<SelectableText>());
    });
  });

  group('tool meta', () {
    test('details and labels', () {
      expect(toolDetail(_item('Grep', {'pattern': 'TODO', 'path': 'a/b/c/lib', 'glob': '*.dart', '-i': true, 'output_mode': 'content'})),
          'TODO · in .../c/lib · *.dart · -i · content');
      final fetch = _item('WebFetch', {'url': 'https://example.com/docs/a?x=1'});
      expect(toolDetail(fetch), 'example.com/docs/a');
      expect(toolLabel(fetch, toolDetail(fetch)), isNull);
      final mcp = _item('mcp__agentmux__WhoAmI', {});
      expect(toolLabel(mcp, ''), 'agentmux · WhoAmI');
      expect(toolIcon(toolKind('mcp__x__y')), '🛠️');
      expect(toolDetailIsPath(_item('Read', {})), isTrue);
      expect(toolDetailIsPath(_item('Bash', {})), isFalse);
    });

    test('pills', () {
      expect(toolPill(_item('Bash', {}, result: '<exited 0 in 0.1s>\nok'))!.label, 'exit 0');
      expect(toolPill(_item('Bash', {}, result: '<exited 1 in 0.1s>\n'))!.color, FeedColors.errorText);
      expect(toolPill(_item('Bash', {}, result: 'no exit line')), isNull);
      expect(toolPill(_item('Write', {'content': 'x' * 2048}))!.label, '2.0 KB');
      expect(toolPill(_item('Edit', {}))!.label, 'edited');
      expect(toolPill(_item('Grep', {}, result: 'Found 3 files\na\nb\nc'))!.label, '3 files');
      expect(toolPill(_item('Grep', {'output_mode': 'content'}, result: 'a:1:x\nb:2:y'))!.label, '2 matches');
      expect(toolPill(_item('Glob', {}, result: 'a.dart\nb.dart'))!.label, '2 files');
      expect(
        toolPill(_item('WebSearch', {}, result: 'Links: [{"title":"A","url":"https://a.example"}]'))!.label,
        '1 source',
      );
      expect(toolPill(_item('Bash', {}, state: ToolState.running, result: '<exited 0 in 1s>')), isNull);
    });

    test('Read range from the call while running', () {
      expect(readRange(_item('Read', {'offset': 10, 'limit': 5}, state: ToolState.running)), '10:14');
    });
  });

  test('lineDiff keeps common lines and marks the change', () {
    final d = lineDiff('a\nb\nc\nd', 'a\nB\nc\nd\ne');
    expect(d.map((l) => '${l.op.name[0]}${l.text}'), ['sa', 'rb', 'aB', 'sc', 'sd', 'ae']);
    final big = lineDiff('x\ny', 'p\nq', maxCells: 1);
    expect(big.map((l) => l.op), [DiffOp.removed, DiffOp.removed, DiffOp.added, DiffOp.added]);
  });

  group('disclosure', () {
    test('running open; finished closed; held open; content-first open', () {
      final d = FeedDisclosure();
      final t = _item('Bash', {}, state: ToolState.running);
      expect(d.isOpen(t), isTrue);
      t.state = ToolState.done;
      expect(d.isOpen(t), isFalse);
      d.hold(t.key);
      expect(d.isOpen(t), isTrue);
      d.release(t.key);
      expect(d.isOpen(t), isFalse);
      expect(d.isOpen(_item('WebSearch', {})), isTrue);
      expect(d.isOpen(_item('AskUserQuestion', {}, state: ToolState.running)), isFalse);
    });

    test('a held call that was dismissed closes', () {
      final d = FeedDisclosure();
      final t = _item('Bash', {}, state: ToolState.cancelled);
      d.hold(t.key);
      expect(d.isOpen(t), isFalse);
    });

    test('a tap pins a closed call and closes an open one', () {
      final d = FeedDisclosure();
      final t = _item('Bash', {});
      d.toggle(t);
      expect(d.isOpen(t), isTrue);
      d.toggle(t);
      expect(d.isOpen(t), isFalse);
      final running = _item('Read', {}, state: ToolState.running, key: 1);
      d.toggle(running);
      expect(d.isOpen(running), isFalse);
      running.state = ToolState.done;
      expect(d.isOpen(running), isFalse);
      d.clear();
      expect(d.isOpen(t), isFalse);
    });
  });

  group('header', () {
    testWidgets('glyph, icon, label, detail, duration and pill', (tester) async {
      final t = _item('Bash', {'command': 'git status'}, result: '<exited 0 in 0.4s>\nclean')..durationMs = 400;
      await tester.pumpWidget(_host(ToolBlock(tool: t, open: false)));
      final text = _allText(tester);
      for (final s in ['✓', '🔧', 'Bash', 'git status', '(0.4s)', 'exit 0']) {
        expect(text, contains(s));
      }
      final bar = tester.widget<Container>(find.descendant(of: find.byType(ToolBlock), matching: find.byType(Container)).first);
      expect(((bar.decoration! as BoxDecoration).border! as Border).left.color, FeedColors.success);
    });

    testWidgets('on a narrow screen the pill goes first', (tester) async {
      final t = _item('Bash', {'command': 'ls'}, result: '<exited 0 in 0.4s>\n');
      await tester.pumpWidget(_host(ToolBlock(tool: t, open: false), width: 300));
      expect(_allText(tester), isNot(contains('exit 0')));
      expect(_allText(tester), contains('ls'));
    });

    testWidgets('a long tool name on a narrow row does not overflow', (tester) async {
      final t = _item('mcp__a_rather_long_server_name__an_even_longer_tool_name_here', {})
        ..durationMs = 12345;
      await tester.pumpWidget(_host(ToolBlock(tool: t, open: false), width: 260));
      expect(tester.takeException(), isNull);
    });

    test('a long path is cut from the left', () {
      const style = TextStyle(fontSize: 12);
      const path = 'C:/Users/someone/projects/agentmux/lib/features/feed/transcript.dart';
      final shown = fitFromLeft(path, style, 250, TextScaler.noScaling);
      expect(shown, startsWith('…'));
      expect(shown, endsWith('transcript.dart'));
      expect(fitFromLeft('a.dart', style, 150, TextScaler.noScaling), 'a.dart');
    });
  });

  group('previews', () {
    testWidgets('Bash: output, stderr in red, the exit code', (tester) async {
      final t = _item('Bash', {'command': 'make'}, state: ToolState.done, result: 'x')
        ..facts = const ToolFacts(stdout: '<exited 2 in 1s>\nbuilding', stderr: 'error: no rule');
      await tester.pumpWidget(_host(ToolPreview(tool: t)));
      final text = _allText(tester);
      expect(text, contains('building'));
      expect(text, isNot(contains('<exited')));
      expect(text, contains('Exit code: 2'));
      final err = tester.widget<SelectableText>(find.ancestor(
        of: find.text('error: no rule'),
        matching: find.byType(SelectableText),
      ));
      expect(err.style?.color, FeedColors.errorText);
    });

    testWidgets('a long log keeps its end', (tester) async {
      final out = List.generate(1500, (i) => 'line $i').join('\n');
      final t = _item('Bash', {}, result: out);
      await tester.pumpWidget(_host(ToolPreview(tool: t)));
      final text = _allText(tester);
      expect(text, contains('… 500 earlier lines hidden'));
      expect(text, contains('line 1499'));
      expect(text, isNot(contains('line 499\n')));
    });

    testWidgets('Edit: a diff with markers and tints', (tester) async {
      final t = _item('Edit', {'file_path': 'lib/a.dart', 'old_string': 'int a = 1;', 'new_string': 'int a = 2;'});
      await tester.pumpWidget(_host(ToolPreview(tool: t)));
      final rows = tester.widgetList<DiffRow>(find.byType(DiffRow)).toList();
      expect(rows.map((r) => r.line.op), [DiffOp.removed, DiffOp.added]);
      expect(_allText(tester), contains('lib/a.dart'));
      final added = tester.widget<Container>(find.descendant(of: find.byWidget(rows[1]), matching: find.byType(Container)).first);
      expect(added.color, FeedColors.tint(FeedColors.successText, 0.15));
    });

    testWidgets('a rebuild keeps the built preview until the call changes', (tester) async {
      final t = _item('Edit', {'file_path': 'a.dart', 'old_string': 'a', 'new_string': 'b'});
      Widget view() => _host(ToolPreview(tool: t));
      await tester.pumpWidget(view());
      final first = tester.widget<DiffRow>(find.byType(DiffRow).first);
      await tester.pumpWidget(view());
      expect(tester.widget<DiffRow>(find.byType(DiffRow).first), same(first));
      t.input = {'file_path': 'a.dart', 'old_string': 'a', 'new_string': 'c'};
      await tester.pumpWidget(view());
      final changed = tester.widget<DiffRow>(find.byType(DiffRow).last);
      expect(changed, isNot(same(first)));
      expect(changed.line.text, 'c');
    });

    testWidgets('Read: a line gutter, highlighted, reminders removed', (tester) async {
      final t = _item('Read', {'file_path': 'lib/a.dart'},
          result: '     1→void main() {}\n     2→// end\n\n<system-reminder>\nnot the file\n</system-reminder>\n');
      await tester.pumpWidget(_host(ToolPreview(tool: t)));
      final text = _allText(tester);
      expect(text, contains('1\n2'));
      expect(text, contains('void main() {}'));
      expect(text, isNot(contains('not the file')));
      expect(text, isNot(contains('→')));
    });

    testWidgets('Read: an empty last line keeps its number in the gutter', (tester) async {
      final t = _item('Read', {'file_path': 'a.py'}, result: '     1\tdef f():\n     2\t    pass\n     3\t\n');
      await tester.pumpWidget(_host(ToolPreview(tool: t)));
      final text = _allText(tester);
      expect(text, contains('1\n2\n3'));
      expect(text, isNot(contains('     3')));
    });

    testWidgets('Write: path, size, content', (tester) async {
      final t = _item('Write', {'file_path': 'notes.txt', 'content': 'hello'}, state: ToolState.running);
      await tester.pumpWidget(_host(ToolPreview(tool: t)));
      final text = _allText(tester);
      expect(text, contains('notes.txt · 5 B'));
      expect(text, contains('hello'));
    });

    testWidgets('JSON opens from a one-line summary', (tester) async {
      final t = _item('mcp__x__list', {}, result: '{"a": 1, "b": [1, 2]}');
      await tester.pumpWidget(_host(ToolPreview(tool: t)));
      expect(find.text('▸ {2 keys}'), findsOneWidget);
      await tester.tap(find.text('▸ {2 keys}'));
      await tester.pump();
      expect(_allText(tester), contains('"b": ['));
    });

    testWidgets('running, cancelled, truncated', (tester) async {
      await tester.pumpWidget(_host(ToolPreview(tool: _item('Grep', {}, state: ToolState.running))));
      expect(_allText(tester), contains('⏳ Thinking…'));
      await tester.pumpWidget(_host(ToolPreview(tool: _item('Grep', {}, state: ToolState.cancelled))));
      expect(_allText(tester), contains('Cancelled'));
      await tester.pumpWidget(_host(ToolPreview(tool: _item('Grep', {})..truncatedBytes = 70000)));
      expect(_allText(tester), contains(truncatedResultText));
    });

    testWidgets('a tall preview offers Taller, which triples it', (tester) async {
      final t = _item('Bash', {}, result: List.generate(100, (i) => 'l$i').join('\n'));
      await tester.pumpWidget(_host(ToolBlock(tool: t, open: true)));
      final before = tester.getSize(find.byType(SingleChildScrollView).last).height;
      await tester.tap(find.text('Taller'));
      await tester.pump();
      final after = tester.getSize(find.byType(SingleChildScrollView).last).height;
      expect(after, greaterThan(before * 2.5));
      expect(find.text('Shorter'), findsOneWidget);
    });
  });
}
