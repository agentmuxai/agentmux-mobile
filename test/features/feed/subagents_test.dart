import 'package:agentmux_mobile/features/feed/tool_block.dart';
import 'package:agentmux_mobile/features/feed/tool_meta.dart';
import 'package:agentmux_mobile/features/feed/transcript.dart';
import 'package:agentmux_mobile/features/feed/working_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'claude_fixtures.dart';

/// A frame the subagent of Agent call [parent] wrote.
String _sub(String parent, Map<String, Object?> f) => frame({...f, 'parent_tool_use_id': parent});

String _subToolUse(String parent, String id, String name, Map<String, Object?> input) => _sub(parent, {
      'type': 'assistant',
      'message': {
        'content': [
          {'type': 'tool_use', 'id': id, 'name': name, 'input': input},
        ],
      },
    });

String _subResult(String parent, String id, String text) => _sub(parent, {
      'type': 'user',
      'message': {
        'content': [
          {'type': 'tool_result', 'tool_use_id': id, 'content': text},
        ],
      },
    });

final _agentCall = toolUse('toolu_agent', 'Agent', {'description': 'Find the flaky test', 'prompt': 'Look'});

void main() {
  test('a subagent\'s calls go under its Agent call, with their results', () {
    final t = Transcript(provider: 'claude')
      ..addFrames([
        _agentCall,
        _sub('toolu_agent', {
          'type': 'user',
          'message': {'content': 'Look'},
        }),
        _sub('toolu_agent', {
          'type': 'assistant',
          'message': {
            'content': [
              {'type': 'text', 'text': 'Searching.'},
            ],
          },
        }),
        _subToolUse('toolu_agent', 'toolu_s1', 'Grep', {'pattern': 'flaky'}),
        _subResult('toolu_agent', 'toolu_s1', 'Found 2 files'),
        _subToolUse('toolu_agent', 'toolu_s2', 'Read', {'file_path': 'test/a_test.dart'}),
      ]);
    // Its prompt and text aren't the main thread's.
    final agent = t.items.single as ToolCallItem;
    expect(agent.steps.map((s) => (s.name, s.state)), [
      ('Grep', ToolState.done),
      ('Read', ToolState.running),
    ]);
    expect(agent.steps.first.result, 'Found 2 files');
    expect(Transcript.runningStep(agent)?.name, 'Read');
    expect(toolPill(agent)!.label, '2 steps');
  });

  test('steps of an Agent call before the snapshot are dropped', () {
    final t = Transcript(provider: 'claude')
      ..addFrames([_subToolUse('toolu_gone', 'toolu_s1', 'Grep', {'pattern': 'x'})]);
    expect(t.items, isEmpty);
  });

  test('the turn\'s end cancels a running step', () {
    final t = Transcript(provider: 'claude')
      ..addFrames([
        _agentCall,
        _subToolUse('toolu_agent', 'toolu_s1', 'Bash', {'command': 'sleep 99'}),
        turnResult(1000),
      ]);
    expect((t.items.single as ToolCallItem).steps.single.state, ToolState.cancelled);
  });

  test('the working row names the running step', () {
    final t = Transcript(provider: 'claude')
      ..addFrames([
        _agentCall,
        _subToolUse('toolu_agent', 'toolu_s1', 'Bash', {'command': 'make test'}),
      ]);
    final text = workingText(
      t.turn,
      runningTool: t.runningTool,
      now: DateTime.now(),
    );
    expect(text, 'Agent · Find the flaky test · Bash · make test');
  });

  testWidgets('"▸ 2 steps" opens to a row per step', (tester) async {
    final t = Transcript(provider: 'claude')
      ..addFrames([
        _agentCall,
        _subToolUse('toolu_agent', 'toolu_s1', 'Grep', {'pattern': 'flaky'}),
        _subResult('toolu_agent', 'toolu_s1', 'Found 2 files'),
        _subToolUse('toolu_agent', 'toolu_s2', 'Read', {'file_path': 'test/a_test.dart'}),
      ]);
    final agent = t.items.single as ToolCallItem;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: ToolBlock(tool: agent, open: true))),
    ));
    expect(find.text('▸ 2 steps · now: Read · test/a_test.dart'), findsOneWidget);
    expect(find.text('flaky'), findsNothing);
    await tester.tap(find.textContaining('2 steps · now'));
    await tester.pump();
    expect(find.text('flaky'), findsOneWidget);
    // A finished step is closed; tapping it opens its result.
    expect(find.textContaining('Found 2 files'), findsNothing);
    await tester.tap(find.text('flaky'));
    await tester.pump();
    expect(find.textContaining('Found 2 files'), findsOneWidget);
  });
}
