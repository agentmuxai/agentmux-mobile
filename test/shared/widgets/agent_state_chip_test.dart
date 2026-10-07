import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentmux_mobile/core/discovery/models/lan_instance.dart';
import 'package:agentmux_mobile/shared/theme/app_theme.dart';
import 'package:agentmux_mobile/shared/widgets/agent_state_chip.dart';
import 'package:agentmux_mobile/shared/widgets/tag_chip.dart';

final t0 = DateTime(2026, 10, 7, 12);

StateSince _since(Duration d, [DateTime? at]) =>
    StateSince(elapsedAtReceipt: d, receivedAt: at ?? t0);

Widget _app(Widget child, {bool disableAnimations = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Scaffold(body: Center(child: child)),
  ),
);

TagChip _tag(WidgetTester tester) => tester.widget<TagChip>(
  find.descendant(
    of: find.byType(AgentStateChip),
    matching: find.byType(TagChip),
  ),
);

double _dotOpacity(WidgetTester tester) =>
    tester
        .widget<FadeTransition>(
          find.descendant(
            of: find.byType(AgentStateChip),
            matching: find.byType(FadeTransition),
          ),
        )
        .opacity
        .value;

void main() {
  group('formatStateDuration', () {
    test('short units for a narrow chip', () {
      expect(formatStateDuration(Duration.zero), '<1m');
      expect(formatStateDuration(const Duration(seconds: 59)), '<1m');
      expect(formatStateDuration(const Duration(minutes: 1)), '1m');
      expect(
        formatStateDuration(const Duration(minutes: 59, seconds: 59)),
        '59m',
      );
      expect(formatStateDuration(const Duration(hours: 1)), '1h');
      expect(
        formatStateDuration(const Duration(hours: 23, minutes: 59)),
        '23h',
      );
      expect(formatStateDuration(const Duration(days: 3, hours: 2)), '3d');
    });
  });

  group('AgentStateView', () {
    test('each state says what it means in words', () {
      String label(AgentState s) => AgentStateView.of(s, now: t0).label;
      expect(label(AgentState.working), 'working');
      expect(label(AgentState.waiting), 'needs you');
      expect(label(AgentState.idle), 'idle');
      expect(label(AgentState.stopped), 'stopped');
      expect(label(AgentState.error), 'error');
    });

    test('a working agent shows how long, counted on the device clock', () {
      final since = _since(const Duration(minutes: 3));
      var v = AgentStateView.of(AgentState.working, since: since, now: t0);
      expect(v.label, 'working 3m');
      expect(v.muted, isFalse);
      expect(v.nextChange, const Duration(minutes: 1));
      v = AgentStateView.of(
        AgentState.working,
        since: since,
        now: t0.add(const Duration(minutes: 2, seconds: 30)),
      );
      expect(v.label, 'working 5m');
      expect(v.nextChange, const Duration(seconds: 30));
    });

    test('only a working agent shows a duration', () {
      final since = _since(const Duration(minutes: 3));
      for (final s in [
        AgentState.waiting,
        AgentState.idle,
        AgentState.stopped,
        AgentState.error,
      ]) {
        final v = AgentStateView.of(s, since: since, now: t0);
        expect(v.label, isNot(contains('3m')), reason: '$s');
        expect(v.nextChange, isNull, reason: '$s');
      }
    });

    test('a channel gone quiet: muted, no duration', () {
      final v = AgentStateView.of(
        AgentState.working,
        since: _since(const Duration(minutes: 3)),
        live: false,
        now: t0,
      );
      expect(v.label, 'working');
      expect(v.muted, isTrue);
      expect(v.nextChange, isNull);
    });

    test('a fresh cloud state is plain, and turns stale after a minute', () {
      final v = AgentStateView.of(
        AgentState.idle,
        asOf: t0.subtract(const Duration(seconds: 20)),
        now: t0,
      );
      expect(v.label, 'idle');
      expect(v.muted, isFalse);
      expect(v.nextChange, const Duration(seconds: 40));
    });

    test('a cloud state older than a minute says how old, muted', () {
      var v = AgentStateView.of(
        AgentState.working,
        asOf: t0.subtract(const Duration(seconds: 90)),
        now: t0,
      );
      expect(v.label, 'working, as of 1m ago');
      expect(v.tooltip, contains('last reported 1m ago'));
      expect(v.muted, isTrue);
      expect(v.nextChange, const Duration(seconds: 30));
      v = AgentStateView.of(
        AgentState.waiting,
        asOf: t0.subtract(const Duration(hours: 2)),
        now: t0,
      );
      expect(v.label, 'needs you, as of 2h ago');
    });

    test("a relay clock ahead of the device's counts as fresh", () {
      final v = AgentStateView.of(
        AgentState.idle,
        asOf: t0.add(const Duration(minutes: 5)),
        now: t0,
      );
      expect(v.label, 'idle');
      expect(v.muted, isFalse);
    });
  });

  group('AgentStateChip', () {
    test('an agent with no state gets no chip', () {
      expect(AgentStateChip.forAgent(const LanAgent(name: 'Old')), isNull);
      final chip =
          AgentStateChip.forAgent(
            LanAgent(
              name: 'New',
              state: AgentState.idle,
              stateSince: _since(Duration.zero),
            ),
            live: false,
          )!;
      expect(chip.state, AgentState.idle);
      expect(chip.live, isFalse);
    });

    testWidgets('each state: its words and its colour', (tester) async {
      final cases = {
        AgentState.working: ('working', AppColors.success, true),
        AgentState.waiting: ('needs you', AppColors.warning, true),
        AgentState.idle: ('idle', AppColors.textSecondary, true),
        AgentState.stopped: ('stopped', AppColors.textSecondary, false),
        AgentState.error: ('error', AppColors.error, true),
      };
      for (final MapEntry(key: state, value: (label, color, filled))
          in cases.entries) {
        await tester.pumpWidget(_app(AgentStateChip(state: state)));
        expect(find.text(label), findsOneWidget, reason: '$state');
        final tag = _tag(tester);
        expect(tag.color, color, reason: '$state');
        expect(tag.filled, filled, reason: '$state');
        // Only a working agent has the dot.
        expect(
          find.descendant(
            of: find.byType(AgentStateChip),
            matching: find.byType(FadeTransition),
          ),
          state == AgentState.working ? findsOneWidget : findsNothing,
          reason: '$state',
        );
      }
    });

    testWidgets('the working duration ticks over on its own', (tester) async {
      final since = _since(const Duration(seconds: 50), clock.now());
      await tester.pumpWidget(
        _app(AgentStateChip(state: AgentState.working, since: since)),
      );
      expect(find.text('working <1m'), findsOneWidget);
      await tester.pump(const Duration(seconds: 11));
      expect(find.text('working 1m'), findsOneWidget);
      await tester.pump(const Duration(minutes: 1));
      expect(find.text('working 2m'), findsOneWidget);
    });

    testWidgets('a cloud state goes stale on its own', (tester) async {
      await tester.pumpWidget(
        _app(
          AgentStateChip(
            state: AgentState.idle,
            asOf: clock.now().subtract(const Duration(seconds: 50)),
          ),
        ),
      );
      expect(find.text('idle'), findsOneWidget);
      expect(find.byType(Opacity), findsNothing);
      await tester.pump(const Duration(seconds: 11));
      expect(find.text('idle, as of 1m ago'), findsOneWidget);
      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0.55);
    });

    testWidgets('the dot pulses while working', (tester) async {
      await tester.pumpWidget(
        _app(const AgentStateChip(state: AgentState.working)),
      );
      final start = _dotOpacity(tester);
      await tester.pump(const Duration(milliseconds: 450));
      expect(_dotOpacity(tester), isNot(start));
    });

    testWidgets('no pulse when the platform asks for no animations', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const AgentStateChip(state: AgentState.working),
          disableAnimations: true,
        ),
      );
      expect(_dotOpacity(tester), 1);
      await tester.pump(const Duration(milliseconds: 450));
      expect(_dotOpacity(tester), 1);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('no pulse for a channel gone quiet', (tester) async {
      await tester.pumpWidget(
        _app(const AgentStateChip(state: AgentState.working, live: false)),
      );
      await tester.pump(const Duration(milliseconds: 450));
      expect(_dotOpacity(tester), 1);
    });
  });
}
