import 'package:agentmux_mobile/core/discovery/models/lan_instance.dart';
import 'package:agentmux_mobile/core/viewer/feed_events.dart';
import 'package:agentmux_mobile/features/feed/agent_feed_screen.dart';
import 'package:agentmux_mobile/shared/widgets/agent_state_chip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final tapped = DateTime.utc(2026, 10, 7, 12);
  final listed = LanAgent(
    name: 'AgentA',
    state: AgentState.idle,
    stateSince: StateSince(
      elapsedAtReceipt: const Duration(minutes: 7),
      receivedAt: tapped,
    ),
  );

  test('before any status event: the host list\'s state', () {
    final chip = feedStateChip(agent: listed)!;
    expect(chip.state, AgentState.idle);
    expect(chip.since, listed.stateSince);
    expect(chip.live, isTrue);
  });

  test('no state anywhere: no chip', () {
    expect(feedStateChip(agent: const LanAgent(name: 'AgentA')), isNull);
  });

  test('a status event wins, its duration from the desktop\'s own clock', () {
    final received = tapped.add(const Duration(seconds: 30));
    final chip = feedStateChip(
      agent: listed,
      status: const FeedStatus(
        state: 'working',
        sinceMs: 1000000,
        nowMs: 1000000 + 3 * 60 * 1000,
      ),
      statusReceivedAt: received,
    )!;
    expect(chip.state, AgentState.working);
    expect(
      chip.since,
      StateSince(
        elapsedAtReceipt: const Duration(minutes: 3),
        receivedAt: received,
      ),
    );
    // What the chip says a minute later on this device's clock.
    final view = AgentStateView.of(
      chip.state,
      since: chip.since,
      now: received.add(const Duration(minutes: 1)),
    );
    expect(view.label, 'working 4m');
  });

  test('a status without both times has no duration', () {
    final chip = feedStateChip(
      agent: listed,
      status: const FeedStatus(state: 'working', sinceMs: 1000),
      statusReceivedAt: tapped,
    )!;
    expect(chip.state, AgentState.working);
    expect(chip.since, isNull);
  });

  test('an unknown state from the feed shows no chip, not the stale one', () {
    expect(
      feedStateChip(
        agent: listed,
        status: const FeedStatus(state: 'compacting'),
        statusReceivedAt: tapped,
      ),
      isNull,
    );
  });

  test('not live (reconnecting, paused): muted', () {
    expect(feedStateChip(agent: listed, live: false)!.live, isFalse);
    expect(
      feedStateChip(
        agent: listed,
        status: const FeedStatus(state: 'idle'),
        statusReceivedAt: tapped,
        live: false,
      )!
          .live,
      isFalse,
    );
  });
}
