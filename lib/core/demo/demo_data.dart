// Static sample data for demo mode (see docs/specs/APP_STORE_SUBMISSION_READINESS.md).
//
// This exists so anyone opening the app without a LAN AgentMux instance or a
// real Cognito account — most notably an App Store reviewer — can still see
// what the agent list, message feed, and statuses actually look like. Timestamps
// are computed relative to `DateTime.now()` at call time (not baked into fixed
// ISO strings) so the "Active now" / "Xm ago" labels always look plausible no
// matter when the screen is opened. No network call is ever made on this path.
import '../discovery/host_tree.dart';
import '../discovery/models/lan_instance.dart';
import '../fleet/fleet_store.dart';
import '../models/agent.dart';
import '../models/message.dart';

/// Sample hosts for the demo host tree: one of each platform and each route,
/// one host running channels it does not share on the LAN, and both agent
/// kinds, so every tag the real screen can show appears here
/// (`docs/specs/SPEC_FLEET_HOST_TAGS_AND_CLOUD_HOSTS_2026_10_06.md`), and an
/// agent in each state, so every status chip does too
/// (`docs/specs/SPEC_AGENT_STATUS_AND_LIVE_PANE_FEED_2026_10_07.md`). The
/// addresses are documentation placeholders; nothing is ever contacted.
List<HostNode> buildDemoHosts() {
  final now = DateTime.now();
  StateSince since(Duration d) =>
      StateSince(elapsedAtReceipt: d, receivedAt: now);
  FleetEntry entry(
    String hostname,
    String address, {
    required String os,
    required ChannelRoute route,
    required String channel,
    required List<LanAgent> agents,
    int? channelsRunning,
  }) =>
      FleetEntry(
        instance: LanInstance(
          hostname: hostname,
          version: '0.59.11',
          address: address,
          port: 29700,
          authKey: '',
          channel: channel,
          os: os,
          channelsRunning: channelsRunning,
          agents: agents,
        ),
        route: route,
        lastSeen: now,
      );

  return buildHostTrees([
    entry('atlas', '198.51.100.10',
        os: 'windows',
        route: ChannelRoute.lan,
        channel: 'stable',
        agents: [
          LanAgent(
            name: 'Nova',
            kind: AgentKind.host,
            state: AgentState.working,
            stateSince: since(const Duration(minutes: 3)),
          ),
          LanAgent(
            name: 'Piper',
            kind: AgentKind.host,
            state: AgentState.waiting,
            stateSince: since(const Duration(minutes: 1)),
          ),
        ]),
    entry('forge', '198.51.100.20',
        os: 'linux',
        route: ChannelRoute.lanAndCloud,
        channel: 'stable',
        channelsRunning: 3,
        agents: [
          LanAgent(
            name: 'Ember',
            kind: AgentKind.container,
            state: AgentState.idle,
            stateSince: since(const Duration(minutes: 12)),
          ),
          LanAgent(
            name: 'Relay',
            kind: AgentKind.host,
            state: AgentState.error,
            stateSince: since(const Duration(hours: 6)),
          ),
        ]),
    entry('orbit', '',
        os: 'macos',
        route: ChannelRoute.cloud,
        channel: 'stable',
        agents: [
          // A cloud record carries no duration; this one is a minute and a
          // half old, so its chip says how old it is.
          LanAgent(
            name: 'Scout',
            kind: AgentKind.container,
            state: AgentState.working,
            stateAsOf: now.subtract(const Duration(seconds: 90)),
          ),
        ]),
    entry('lab', '203.0.113.7',
        os: 'linux',
        route: ChannelRoute.direct,
        channel: 'stable',
        agents: [
          LanAgent(
            name: 'Quill',
            kind: AgentKind.host,
            state: AgentState.stopped,
            stateSince: since(const Duration(hours: 2)),
          ),
        ]),
  ]);
}

List<Agent> buildDemoAgents() {
  final now = DateTime.now().toUtc();
  return [
    Agent(
      id: 'Nova',
      lastSeen: now.subtract(const Duration(seconds: 20)).toIso8601String(),
      messagesSent: 128,
    ),
    Agent(
      id: 'Piper',
      lastSeen: now.subtract(const Duration(minutes: 12)).toIso8601String(),
      messagesSent: 42,
    ),
    Agent(
      id: 'Scout',
      lastSeen: now.subtract(const Duration(minutes: 3)).toIso8601String(),
      messagesSent: 7,
    ),
    Agent(
      id: 'Relay',
      lastSeen: now.subtract(const Duration(hours: 6)).toIso8601String(),
      messagesSent: 301,
    ),
  ];
}

List<Message> buildDemoMessages(String agentId) {
  final now = DateTime.now().toUtc();
  Message m(int minutesAgo, String from, String to, String text,
      {String priority = 'normal'}) {
    return Message(
      id: '$agentId-$minutesAgo',
      fromAgent: from,
      toAgent: to,
      message: text,
      priority: priority,
      timestamp: now.subtract(Duration(minutes: minutesAgo)).toIso8601String(),
      read: minutesAgo > 5,
    );
  }

  return switch (agentId) {
    'Nova' => [
        m(1, 'Nova', 'you', 'Build is green — deploy preview is up.'),
        m(18, 'you', 'Nova', 'Can you re-run the flaky integration test?'),
        m(45, 'Nova', 'you', 'Found the root cause, opening a PR now.',
            priority: 'high'),
      ],
    'Piper' => [
        m(12, 'Piper', 'you', 'Docs draft ready for review.'),
        m(90, 'you', 'Piper', 'Ping me when the API reference section is done.'),
      ],
    'Ember' => [
        m(2, 'Ember', 'you', 'Sandbox rebuilt from a clean image, tests pass.'),
        m(30, 'you', 'Ember', 'Try the migration in the sandbox first.'),
      ],
    'Quill' => [
        m(8, 'Quill', 'you', 'Release notes drafted for the next version.'),
      ],
    'Scout' => [
        m(3, 'Scout', 'you', 'Crawled 240 pages, 3 broken links found.',
            priority: 'urgent'),
        m(20, 'you', 'Scout', 'Start the weekly link-check sweep.'),
      ],
    _ => [
        m(360, 'Relay', 'you', 'Nightly sync finished, no conflicts.'),
        m(420, 'you', 'Relay', 'Kick off the nightly sync a bit earlier today.'),
      ],
  };
}
