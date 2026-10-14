import 'package:agentmux_mobile/core/discovery/models/lan_instance.dart';
import 'package:agentmux_mobile/features/feed/transcript.dart';
import 'package:agentmux_mobile/features/feed/working_row.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'claude_fixtures.dart';

String _event(Map<String, Object?> e) => frame({'type': 'stream_event', 'event': e});
String _messageStart(String id, [int out = 1]) => _event({
      'type': 'message_start',
      'message': {
        'id': id,
        'usage': {'output_tokens': out},
      },
    });
String _blockStart(String type) => _event({
      'type': 'content_block_start',
      'index': 0,
      'content_block': {'type': type, if (type == 'text') 'text': ''},
    });
String _messageDelta(int out) => _event({
      'type': 'message_delta',
      'usage': {'output_tokens': out},
    });
final _messageStop = _event({'type': 'message_stop'});

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('turn', () {
    test('a prompt opens it; streamed output counts, across messages', () {
      final at = DateTime(2026, 10, 13, 12);
      final t = Transcript(provider: 'claude')..addFrames([userPrompt('Go')], at: at);
      expect(t.turn.open, isTrue);
      expect(t.turn.startedAt, at);
      expect(t.turn.phase, TurnPhase.requesting);
      t.addFrames([_messageStart('m1'), _blockStart('thinking'), _messageDelta(1200)]);
      expect(t.turn.phase, TurnPhase.thinking);
      expect(t.turn.outputTokens, 1200);
      t.addFrames([_messageStop]);
      expect(t.turn.phase, TurnPhase.requesting);
      t.addFrames([_messageStart('m2'), _blockStart('text'), _messageDelta(300)]);
      expect(t.turn.phase, TurnPhase.writing);
      expect(t.turn.outputTokens, 1500);
      // The whole message after its stream isn't counted again.
      t.addFrames([
        frame({
          'type': 'assistant',
          'message': {
            'id': 'm2',
            'content': [
              {'type': 'text', 'text': 'Done'},
            ],
            'usage': {'output_tokens': 300},
          },
        }),
      ]);
      expect(t.turn.outputTokens, 1500);
    });

    test('a whole message with no stream counts once', () {
      final t = Transcript(provider: 'claude')
        ..addFrames([
          userPrompt('Go'),
          frame({
            'type': 'assistant',
            'message': {
              'id': 'm1',
              'content': [
                {'type': 'text', 'text': 'Hi'},
              ],
              'usage': {'output_tokens': 40},
            },
          }),
        ]);
      expect(t.turn.outputTokens, 40);
    });

    test('the result ends it: how long, and what it wrote', () {
      final t = Transcript(provider: 'claude')
        ..addFrames([
          userPrompt('Go'),
          frame({
            'type': 'result',
            'duration_ms': 42000,
            'usage': {'output_tokens': 2400},
          }),
        ]);
      expect(t.turn.open, isFalse);
      expect(t.turn.last, (durationMs: 42000, outputTokens: 2400));
    });

    test('the Worked line counts this turn, not the session', () {
      final t = Transcript(provider: 'claude')
        ..addFrames([
          userPrompt('Again'),
          _messageStart('m9'),
          _messageDelta(300),
          _messageStop,
          frame({
            'type': 'result',
            'duration_ms': 5000,
            // Session-wide in streaming-input mode.
            'usage': {'output_tokens': 98000},
          }),
        ]);
      expect(t.turn.last, (durationMs: 5000, outputTokens: 300));
    });

    test('a rate limit, until the next request starts', () {
      final at = DateTime(2026, 10, 13, 12);
      final t = Transcript(provider: 'claude')
        ..addFrames([
          userPrompt('Go'),
          frame({
            'type': 'rate_limit_event',
            'rate_limit_info': {'status': 'rejected'},
            'retry_after_ms': 30000,
          }),
        ], at: at);
      expect(t.turn.rateLimited, isTrue);
      expect(t.turn.retryAt, at.add(const Duration(seconds: 30)));
      t.addFrames([_messageStart('m1')]);
      expect(t.turn.rateLimited, isFalse);
    });

    test('allowed rate limit events change nothing', () {
      final t = Transcript(provider: 'claude')
        ..addFrames([
          userPrompt('Go'),
          frame({
            'type': 'rate_limit_event',
            'rate_limit_info': {'status': 'allowed_warning'},
          }),
        ]);
      expect(t.turn.rateLimited, isFalse);
    });

    test('output with no prompt seen opens a turn', () {
      final t = Transcript(provider: 'claude')..addFrames([_messageStart('m1')]);
      expect(t.turn.open, isTrue);
      expect(t.turn.startedAt, isNull);
    });

    test('an interrupt ends it with no Worked line', () {
      final t = Transcript(provider: 'claude')
        ..addFrames([
          userPrompt('Go'),
          frame({
            'type': 'user',
            'message': {
              'content': [
                {'type': 'text', 'text': '[Request interrupted by user]'},
              ],
            },
          }),
        ]);
      expect(t.turn.open, isFalse);
      expect(t.turn.last, isNull);
    });
  });

  group('what the row says', () {
    final now = DateTime(2026, 10, 13, 12);
    TurnInfo turn(TurnPhase phase) => TurnInfo()
      ..open = true
      ..phase = phase;

    test('by phase', () {
      expect(workingText(turn(TurnPhase.thinking), now: now), 'Thinking');
      expect(workingText(turn(TurnPhase.writing), now: now), 'Writing the reply');
      expect(workingText(turn(TurnPhase.composing), now: now), 'Preparing the next step');
      expect(workingText(turn(TurnPhase.requesting), now: now), 'Working…');
    });

    test('a running tool, with its time once it is slow', () {
      final tool = ToolCallItem(0, id: 't', name: 'Bash', input: {'command': 'make test'})
        ..receivedAt = now.subtract(const Duration(seconds: 3));
      expect(workingText(turn(TurnPhase.composing), runningTool: tool, now: now), 'Bash · make test');
      tool.receivedAt = now.subtract(const Duration(seconds: 75));
      expect(workingText(turn(TurnPhase.composing), runningTool: tool, now: now), 'Bash · make test · 1m 15s');
    });

    test('most urgent first: a question, compaction, a rate limit', () {
      final ask = ToolCallItem(0, id: 'q', name: 'AskUserQuestion');
      final limited = turn(TurnPhase.requesting)
        ..rateLimited = true
        ..retryAt = now.add(const Duration(seconds: 12));
      expect(workingText(limited, runningTool: ask, compacting: true, now: now),
          'Waiting for your answer on the computer');
      expect(workingText(limited, compacting: true, now: now), 'Compacting…');
      expect(workingText(limited, now: now), 'Rate limited — retrying in 12s');
      limited.retryAt = null;
      expect(workingText(limited, now: now), 'Rate limited — retrying…');
    });

    test('the arrow: up while a request is in flight, down while a tool runs', () {
      final t = turn(TurnPhase.requesting);
      expect(tokenArrow(t, null), '↑');
      expect(tokenArrow(t, ToolCallItem(0, id: 't', name: 'Bash')), '↓');
      expect(tokenArrow(turn(TurnPhase.writing), null), '↓');
    });

    test('elapsed time', () {
      expect(formatElapsed(const Duration(seconds: 42)), '42s');
      expect(formatElapsed(const Duration(seconds: 65)), '1m 5s');
      expect(formatElapsed(const Duration(minutes: 62)), '1h 2m');
    });
  });

  group('the row', () {
    testWidgets('while working: spinner, words, tokens and time', (tester) async {
      final now = DateTime(2026, 10, 13, 12);
      await withClock(Clock.fixed(now), () async {
        final t = TurnInfo()
          ..open = true
          ..phase = TurnPhase.writing
          ..outputTokens = 2400;
        await tester.pumpWidget(_host(WorkingRow(
          turn: t,
          state: AgentState.working,
          since: StateSince(elapsedAtReceipt: const Duration(seconds: 65), receivedAt: now),
        )));
        expect(find.text('Writing the reply'), findsOneWidget);
        expect(find.text('↓ 2.4k tokens · 1m 5s'), findsOneWidget);
        expect(find.text('⠋'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 130));
        expect(find.text('⠙'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      });
    });

    testWidgets('after the turn: the Worked line', (tester) async {
      final t = TurnInfo()..last = (durationMs: 42000, outputTokens: 2400);
      await tester.pumpWidget(_host(WorkingRow(turn: t, state: AgentState.idle)));
      expect(find.text('✓ Worked · 42s · 2.4k tokens'), findsOneWidget);
    });

    testWidgets('a turn the agent says it stopped shows nothing', (tester) async {
      final t = TurnInfo()..open = true;
      await tester.pumpWidget(_host(WorkingRow(turn: t, state: AgentState.idle)));
      expect(find.byType(Text), findsNothing);
      expect(workingRowLive(t, AgentState.idle), isFalse);
      expect(workingRowLive(t, null), isTrue);
    });
  });
}
