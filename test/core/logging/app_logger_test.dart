import 'package:agentmux_mobile/core/logging/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => AppLogger.clear());

  test('log() prepends newest entry first', () {
    AppLogger.log('first', name: 'Test');
    AppLogger.log('second', name: 'Test');

    expect(AppLogger.entries.map((e) => e.message), ['second', 'first']);
  });

  test('log() retains error and stackTrace', () {
    final error = StateError('boom');
    final stackTrace = StackTrace.current;
    AppLogger.log('failed', name: 'Test', error: error, stackTrace: stackTrace);

    final entry = AppLogger.entries.single;
    expect(entry.error, error);
    expect(entry.stackTrace, stackTrace);
    expect(entry.format(), contains('boom'));
  });

  test('ring buffer caps at 200 entries, dropping the oldest', () {
    for (var i = 0; i < 205; i++) {
      AppLogger.log('entry $i', name: 'Test');
    }

    expect(AppLogger.entries.length, 200);
    expect(AppLogger.entries.first.message, 'entry 204');
    expect(AppLogger.entries.last.message, 'entry 5');
  });

  test('clear() empties the buffer', () {
    AppLogger.log('one', name: 'Test');
    AppLogger.clear();

    expect(AppLogger.entries, isEmpty);
  });
}
