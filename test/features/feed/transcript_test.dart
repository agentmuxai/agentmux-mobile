import 'package:agentmux_mobile/features/feed/transcript.dart';
import 'package:agentmux_mobile/features/feed/transcript_view.dart';
import 'package:flutter_test/flutter_test.dart';

import 'claude_fixtures.dart';

void main() {
  group('Claude-shaped frames', () {
    late List<TranscriptItem> items;

    setUp(() {
      items = (Transcript(provider: 'claude')..addFrames(claudeTurn)).items;
    });

    test('in order: prompt, text, tools, text, divider; thinking hidden', () {
      expect(items.map((i) => i.runtimeType), [
        PromptItem,
        AssistantTextItem,
        ToolCallItem,
        ToolCallItem,
        ToolCallItem,
        ToolCallItem,
        AssistantTextItem,
        TurnDividerItem,
      ]);
      expect((items[0] as PromptItem).text, 'Fix the failing test');
      expect((items[1] as AssistantTextItem).text, 'Looking at the test first.');
      for (final i in items) {
        if (i is AssistantTextItem) expect(i.text, isNot(contains('private')));
      }
    });

    test('a tool call with its result', () {
      final bash = items[2] as ToolCallItem;
      expect(bash.name, 'Bash');
      expect(bash.summary, 'git status');
      expect(bash.state, ToolState.done);
      expect(bash.result, 'On branch main\nnothing to commit');
    });

    test('a failed tool call', () {
      final edit = items[3] as ToolCallItem;
      expect(edit.summary, 'lib/app.dart');
      expect(edit.state, ToolState.failed);
      expect(edit.result, 'String to replace not found');
    });

    test('a truncated result attaches to its tool call', () {
      final read = items[4] as ToolCallItem;
      expect(read.summary, 'lib/main.dart');
      expect(read.state, ToolState.done);
      expect(read.truncatedBytes, 70000);
      expect(read.result, isNull);
    });

    test('a call without a result yet is running', () {
      final grep = items[5] as ToolCallItem;
      expect(grep.summary, 'TODO');
      expect(grep.state, ToolState.running);
    });

    test('the turn divider carries the duration', () {
      final d = items.last as TurnDividerItem;
      expect(d.durationMs, 65000);
      expect(d.error, isNull);
      expect(formatTurnDuration(65000), '1m 05s');
      expect(formatTurnDuration(4200), '4.2s');
      expect(formatTurnDuration(38000), '38s');
      expect(formatTurnDuration(3720000), '1h 02m');
    });
  });

  test('a result arriving in a later batch completes the call', () {
    final t = Transcript(provider: 'claude')
      ..addFrames([toolUse('toolu_9', 'Bash', {'command': 'ls'})]);
    expect((t.items.single as ToolCallItem).state, ToolState.running);
    t.addFrames([toolResult('toolu_9', [
      {'type': 'text', 'text': 'a'},
      {'type': 'text', 'text': 'b'},
    ])]);
    final tool = t.items.single as ToolCallItem;
    expect(tool.state, ToolState.done);
    expect(tool.result, 'a\nb');
  });

  test('a cut frame that names no tool is its own line', () {
    final t = Transcript(provider: 'claude')
      ..addFrames([truncated('{"type":"assistant","message"', 90000)]);
    expect((t.items.single as TruncatedItem).bytes, 90000);
    expect(truncatedText, 'Output truncated (open on the computer)');
  });

  test('a turn that ended in an error says so', () {
    final t = Transcript(provider: 'claude')
      ..addFrames([turnResult(1000, isError: true, result: 'API error 529')]);
    expect((t.items.single as TurnDividerItem).error, 'API error 529');
  });

  test('skipped: partial, stream deltas, subagent steps, meta lines, junk', () {
    final t = Transcript(provider: 'qwen')
      ..addFrames([
        frame({
          'type': 'assistant',
          'partial': true,
          'message': {
            'content': [
              {'type': 'text', 'text': 'half'},
            ],
          },
        }),
        frame({
          'type': 'stream_event',
          'event': {'type': 'content_block_delta'},
        }),
        frame({
          'type': 'assistant',
          'parent_tool_use_id': 'toolu_task',
          'message': {
            'content': [
              {'type': 'text', 'text': 'subagent text'},
            ],
          },
        }),
        frame({
          'type': 'user',
          'message': {
            'content': [
              {'type': 'text', 'text': '[Request interrupted by user]'},
            ],
          },
        }),
        'not json',
        '',
      ]);
    expect(t.items, isEmpty);
  });

  test('other providers: the plain text of each frame', () {
    final t = Transcript(provider: 'codex')
      ..addFrames([
        frame({
          'type': 'item.completed',
          'item': {'type': 'agent_message', 'text': 'Done.'},
        }),
        frame({'type': 'turn.started'}),
        'a raw line',
        truncated('{"x"', 80000),
      ]);
    expect(t.items.map((i) => i.runtimeType),
        [PlainTextItem, PlainTextItem, TruncatedItem]);
    expect((t.items[0] as PlainTextItem).text, 'Done.');
    expect((t.items[1] as PlainTextItem).text, 'a raw line');
  });

  test('the oldest items go past the cap', () {
    final t = Transcript(provider: 'claude', maxItems: 3)
      ..addFrames([for (var i = 0; i < 5; i++) userPrompt('p$i')]);
    expect(t.items.map((i) => (i as PromptItem).text), ['p2', 'p3', 'p4']);
  });

  group('toolSummary', () {
    test('the most useful field per tool', () {
      expect(toolSummary('Bash', {'command': 'git status', 'description': 'x'}),
          'git status');
      expect(toolSummary('Edit', {'file_path': 'a.dart', 'old_string': 'x'}),
          'a.dart');
      expect(toolSummary('Grep', {'pattern': 'TODO', 'path': 'lib'}), 'TODO');
      expect(toolSummary('WebFetch', {'url': 'https://example.com/'}),
          'https://example.com/');
      expect(toolSummary('Task', {'description': 'Explore', 'prompt': 'long'}),
          'Explore');
      expect(toolSummary('TodoWrite', {'todos': [1, 2, 3]}), '3 items');
      expect(toolSummary('mcp__x__y', {'query': 'q'}), 'q');
      expect(toolSummary('Mystery', {'n': 1, 'other': 'first string'}),
          'first string');
      expect(toolSummary('Mystery', null), '');
    });

    test('one line, capped', () {
      expect(toolSummary('Bash', {'command': 'a\n  b\tc'}), 'a b c');
      final long = toolSummary('Bash', {'command': 'x' * 500});
      expect(long.length, Transcript.maxSummaryChars + 1);
      expect(long, endsWith('…'));
    });
  });
}
