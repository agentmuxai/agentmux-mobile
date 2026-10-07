import 'dart:convert';

/// Claude Code stream-json frames, as an agent's transcript holds them.
/// Content is made up.
String frame(Map<String, Object?> f) => jsonEncode(f);

final systemInit = frame({
  'type': 'system',
  'subtype': 'init',
  'session_id': 'session-1',
  'model': 'model-x',
});

String userPrompt(String text) => frame({
      'type': 'user',
      'message': {'role': 'user', 'content': text},
    });

String assistantText(String text, {String stop = 'end_turn'}) => frame({
      'type': 'assistant',
      'message': {
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': text},
        ],
        'stop_reason': stop,
      },
    });

String assistantThinking(String text) => frame({
      'type': 'assistant',
      'message': {
        'role': 'assistant',
        'content': [
          {'type': 'thinking', 'thinking': text, 'signature': 'sig'},
        ],
      },
    });

String toolUse(String id, String name, Map<String, Object?> input) => frame({
      'type': 'assistant',
      'message': {
        'role': 'assistant',
        'content': [
          {'type': 'tool_use', 'id': id, 'name': name, 'input': input},
        ],
        'stop_reason': 'tool_use',
      },
    });

String toolResult(String id, Object content, {bool isError = false}) => frame({
      'type': 'user',
      'message': {
        'role': 'user',
        'content': [
          {
            'type': 'tool_result',
            'tool_use_id': id,
            'content': content,
            if (isError) 'is_error': true,
          },
        ],
      },
    });

String turnResult(int durationMs, {bool isError = false, String? result}) =>
    frame({
      'type': 'result',
      'subtype': isError ? 'error_during_execution' : 'success',
      'duration_ms': durationMs,
      'is_error': isError,
      if (result != null) 'result': result,
    });

/// What the desktop sends instead of a frame over 64 KB.
String truncated(String head, int bytes) =>
    frame({'type': 'amx_truncated', 'bytes': bytes, 'head': head});

/// One whole turn: prompt, thinking, text, a Bash call that worked, an Edit
/// that failed, a Read whose result was cut, a Grep still running... then the
/// end of the turn.
final claudeTurn = [
  systemInit,
  userPrompt('Fix the failing test'),
  assistantThinking('private reasoning that is never shown'),
  assistantText('Looking at the test first.', stop: 'tool_use'),
  toolUse('toolu_1', 'Bash', {'command': 'git status', 'description': 'Status'}),
  toolResult('toolu_1', 'On branch main\nnothing to commit'),
  toolUse('toolu_2', 'Edit', {
    'file_path': 'lib/app.dart',
    'old_string': 'a',
    'new_string': 'b',
  }),
  toolResult('toolu_2', 'String to replace not found', isError: true),
  toolUse('toolu_3', 'Read', {'file_path': 'lib/main.dart'}),
  truncated(
    frame({
      'type': 'user',
      'message': {
        'role': 'user',
        'content': [
          {'type': 'tool_result', 'tool_use_id': 'toolu_3', 'content': 'x'},
        ],
      },
    }).substring(0, 100),
    70000,
  ),
  toolUse('toolu_4', 'Grep', {'pattern': 'TODO', 'path': 'lib'}),
  assistantText('Fixed it.'),
  turnResult(65000),
];
